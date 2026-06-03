// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// ─────────────────────────────────────────────────────────────────────────────
//   FEE HOOK V3 — V2 + native partner attribution.
//
//   100% behavioural superset of FeeHookV2. Every V2 admin power, invariant,
//   tier table, custom-fee feature, creator-recipient feature, claim()
//   semantics, and event signature is preserved bit-for-bit.
//
//   What's NEW in v3:
//     - PARTNER WHITELIST: the owner maintains a registry of partner wallets
//       and their share-of-protocol-slice in basis points, via setPartnerBps().
//       A bps of 0 effectively removes a partner. Each partner's bps is hard-
//       capped at MAX_PARTNER_BPS (= 5000, i.e. 50% of the protocol slice),
//       so even a compromised admin cannot drain the protocol slice fully.
//     - PER-TOKEN PARTNER ATTRIBUTION: the launchpad (factory) can attribute
//       a token to a partner atomically AT LAUNCH via setPartnerForTokenAtLaunch().
//       This is a ONE-TIME-WRITE per token, just like creator recipients and
//       custom fees. The OWNER (admin) can override or clear the attribution
//       on ANY token at ANY time via adminSetPartnerForToken().
//     - SWAP-TIME SPLIT: when a token has a partner attribution AND that
//       partner is currently registered (bps > 0), the partner's share is
//       carved out of the PROTOCOL SLICE only — never the creator slice.
//       Creator economics are completely unaffected by partner attribution.
//
//   What's PERMANENTLY immutable (no admin path can ever change these):
//     - everything immutable in V2 (protocolWallet, MAX_FEE_BPS, MAX_CUSTOM_FEE_BPS,
//       MIN_CUSTOM_FEE_BPS, MIN_CREATOR_BPS, SPLIT_DENOM, hook permission bits,
//       claim() always works for whoever has ethOwed > 0, ethOwed balances are
//       never touchable by admin)
//     - MAX_PARTNER_BPS = 5000 (no partner can ever take >50% of the protocol slice)
//     - per-token partner attribution is a ONE-TIME-WRITE by the factory; only
//       the admin can override afterwards
//
//   Note on attribution timing: setPartnerForTokenAtLaunch() always succeeds
//   (factory-only, one-time-write). The partner's CURRENT bps is looked up at
//   each swap, not frozen at launch. This means:
//     - if a token is attributed to a wallet that isn't yet registered as a
//       partner, no partner cut is taken (100% of protocol slice → protocolWallet).
//       If admin later calls setPartnerBps() to register that wallet, the
//       attribution activates automatically for future swaps.
//     - if admin removes a partner via setPartnerBps(partner, 0), all tokens
//       attributed to that partner immediately stop paying the partner cut.
//
//   Already-accrued ethOwed balances are NEVER touched by admin actions —
//   admin moves only redirect FUTURE swap fees.
// ─────────────────────────────────────────────────────────────────────────────

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

interface ILaunchTokenFactory {
    function factory() external view returns (address);
}

/// @notice Optional hot-swappable extension module for the fee hook.
///         Whenever fees accrue on a swap, the hook calls onAccrue() on the
///         currently-installed module (if any) and lets it route a BOUNDED
///         slice of the post-partner protocol slice to a recipient of its
///         choosing. The slice is capped at MAX_MODULE_BPS at the contract
///         level and the call is wrapped in try/catch so a faulty module can
///         never brick swaps — it just gets skipped that swap.
///
///         Use cases: referrals, buybacks, insurance funds, custom rewards,
///         anything that wants a slice of protocol fees on a per-token basis.
///
///         The module CANNOT touch:
///           - the creator slice (untouchable by design)
///           - the partner slice (untouchable by design)
///           - any already-accrued ethOwed balance
///           - the protocolWallet (immutable)
///           - the claim() function
interface IFeeHookModule {
    function onAccrue(
        address token,
        address creator,
        address partner,
        uint256 totalFeeWei,
        uint256 maxModuleCutWei
    ) external returns (address recipient, uint256 cutWei);
}

contract FeeHookV3 is BaseHook, Ownable2Step {
    using StateLibrary for IPoolManager;

    // ── invariants (immutable, no admin path) ───────────────────────────────
    uint256 internal constant TOTAL_SUPPLY = 1_000_000_000 ether;

    /// @notice Hard ceiling on any single fee tier. Even the owner cannot exceed this.
    uint24 public constant MAX_FEE_BPS = 400; // 4.00%
    /// @notice Hard ceiling on a per-token custom fixed fee.
    uint24 public constant MAX_CUSTOM_FEE_BPS = 200; // 2.00%
    /// @notice Hard floor on a per-token custom fixed fee.
    uint24 public constant MIN_CUSTOM_FEE_BPS = 125; // 1.25%
    /// @notice Hard floor on the creator's slice of every fee.
    uint16 public constant MIN_CREATOR_BPS = 1000; // 10%
    /// @notice Split denominator. protocolBps + creatorBps must always equal this.
    uint16 public constant SPLIT_DENOM = 10_000;
    /// @notice Maximum number of tiers in the fee table (sanity bound).
    uint8 public constant MAX_TIERS = 8;
    /// @notice Maximum number of creator-fee recipients per token.
    uint8 public constant MAX_CREATOR_RECIPIENTS = 5;

    /// @notice Hard ceiling on the share of the PROTOCOL SLICE that any single
    ///         partner can take. Even a compromised admin cannot raise a
    ///         partner's bps above this number, so the protocol slice cannot
    ///         be drained beyond 50%. Creator economics are never touched.
    uint16 public constant MAX_PARTNER_BPS = 5000; // 50% of protocol slice

    /// @notice Hard ceiling on the share of the POST-PARTNER PROTOCOL SLICE
    ///         that the extension module can take per swap. Even an admin
    ///         that swaps in a malicious / buggy module cannot route more
    ///         than 30% of the remaining protocol slice through the module.
    ///         Combined with MAX_PARTNER_BPS this guarantees the protocolWallet
    ///         always keeps AT LEAST 35% of the original protocol slice
    ///         (= 50% post-partner × 70% post-module). Creator economics
    ///         are NEVER touched by either the partner or the module.
    uint16 public constant MAX_MODULE_BPS = 3000; // 30% of post-partner protocol slice

    // ── custom-fee auto-decay schedule (immutable, identical to V2) ─────────
    uint256 public constant CUSTOM_FEE_BAND_SIZE_WEI = 75 ether;
    uint16 public constant CUSTOM_FEE_RETAIN_BPS = 8500;
    uint8 public constant CUSTOM_FEE_MAX_REDUCTIONS = 3;

    // ── immutable destination ───────────────────────────────────────────────
    address public immutable protocolWallet;

    // ── mutable fee table ───────────────────────────────────────────────────
    struct Tier {
        uint256 maxMcapEth;
        uint24 bps;
    }

    Tier[] internal _feeTiers;

    uint16 public protocolBps;
    uint16 public creatorBps;

    // ── creator registry (per-token, one-time write, factory-only) ──────────
    mapping(address token => address creator) public creatorOf;

    // ── creator-fee redirection (per-token, one-time-write at launch) ───────
    struct CreatorRecipient {
        address wallet;
        uint16 bps;
    }

    mapping(address token => CreatorRecipient[]) internal _creatorRecipients;

    // ── per-token custom base fee ───────────────────────────────────────────
    mapping(address token => uint24 bps) public customFeeBps;
    bool public customFeesEnabled;

    // ── partner registry (NEW in v3) ────────────────────────────────────────
    /// @notice Per-partner cut of the protocol slice, in bps. 0 means "not
    ///         a partner" — any token attributed to this wallet pays no
    ///         partner cut. Capped at MAX_PARTNER_BPS by setPartnerBps().
    mapping(address partner => uint16 bps) public partnerBpsOf;

    /// @notice Per-token partner attribution. Set ONCE atomically at launch
    ///         by the factory (setPartnerForTokenAtLaunch), or by the admin
    ///         at any time (adminSetPartnerForToken). The bps applied at swap
    ///         time is `partnerBpsOf[partnerOf[token]]` — NOT frozen at
    ///         attribution time, so admin-driven rate changes propagate to
    ///         all tokens attributed to that partner.
    mapping(address token => address partner) public partnerOf;

    // ── extension module (NEW in v3) ────────────────────────────────────────

    /// @notice Optional extension module called on every accrual. address(0)
    ///         disables it entirely (default). Hot-swappable by the owner
    ///         (the Safe) — no timelock, no migration, just one tx. A swap
    ///         can NEVER be bricked by a faulty module: the call is wrapped
    ///         in try/catch and any revert / invalid return is silently
    ///         ignored that swap. See IFeeHookModule docs for the bounds.
    address public hookModule;

    /// @notice Forward-pass gas budget for module calls. Bounded so a buggy
    ///         module can't OOG the swap. 200k is plenty for a few storage
    ///         writes + an event. Owner-tunable within MAX_MODULE_GAS.
    uint64 public moduleGasLimit = 200_000;
    uint64 public constant MAX_MODULE_GAS = 1_000_000;

    // ── pull-based balances ─────────────────────────────────────────────────
    mapping(address => uint256) public ethOwed;

    // ── events ──────────────────────────────────────────────────────────────
    event CreatorRegistered(address indexed token, address indexed creator);
    event FeeAccrued(address indexed token, uint256 totalFeeWei, uint256 creatorWei, uint256 protocolWei);
    event PartnerFeeAccrued(address indexed token, address indexed partner, uint256 partnerWei);
    event Claimed(address indexed who, uint256 amountWei);
    event FeeTiersUpdated(Tier[] tiers);
    event SplitUpdated(uint16 protocolBps, uint16 creatorBps);
    event CreatorRecipientsSet(address indexed token, address indexed setBy, bool byAdmin, CreatorRecipient[] recipients);
    event CustomFeeSet(address indexed token, address indexed setBy, bool byAdmin, uint24 bps);
    event CustomFeesEnabledSet(bool enabled);
    event PartnerBpsSet(address indexed partner, uint16 bps);
    event PartnerForTokenSet(address indexed token, address indexed setBy, bool byAdmin, address indexed partner);
    event HookModuleSet(address indexed oldModule, address indexed newModule);
    event ModuleGasLimitSet(uint64 newLimit);
    event ModuleFeeAccrued(address indexed token, address indexed recipient, uint256 amountWei);
    event ModuleCallFailed(address indexed token, address indexed module);

    // ── errors ──────────────────────────────────────────────────────────────
    error NotTokenFactory();
    error AlreadyRegistered();
    error NothingToClaim();
    error EthTransferFailed();
    error PoolMustHaveEthAsCurrency0();
    error TiersEmpty();
    error TooManyTiers();
    error TierBpsExceedsMax();
    error TiersNotAscending();
    error SplitDenomMismatch();
    error CreatorBpsTooLow();
    error ZeroAddress();
    error CreatorNotRegistered();
    error CreatorRecipientsAlreadySet();
    error TooManyRecipients();
    error RecipientBpsZero();
    error RecipientBpsSumMismatch();
    error CustomFeeOutOfRange();
    error CustomFeeAlreadySet();
    error CustomFeesDisabled();
    error PartnerBpsExceedsMax();
    error PartnerAlreadySet();
    error ModuleGasOutOfRange();

    constructor(
        IPoolManager _poolManager,
        address _protocolWallet,
        address _owner,
        Tier[] memory _initialTiers,
        uint16 _initialProtocolBps,
        uint16 _initialCreatorBps
    ) BaseHook(_poolManager) Ownable(_owner) {
        if (_protocolWallet == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        protocolWallet = _protocolWallet;

        _setFeeTiers(_initialTiers);
        _setSplit(_initialProtocolBps, _initialCreatorBps);
    }

    // ── hook permissions (must match deployed address bits) ─────────────────
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ── creator registration (factory-only, one-time) ───────────────────────
    function registerCreator(address token, address creator) external {
        if (ILaunchTokenFactory(token).factory() != msg.sender) revert NotTokenFactory();
        if (creatorOf[token] != address(0)) revert AlreadyRegistered();
        if (creator == address(0)) revert ZeroAddress();
        creatorOf[token] = creator;
        emit CreatorRegistered(token, creator);
    }

    // ── swap callbacks ──────────────────────────────────────────────────────

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (Currency.unwrap(key.currency0) != address(0)) revert PoolMustHaveEthAsCurrency0();

        bool exactInput = params.amountSpecified < 0;
        bool ethIsSpecified = (params.zeroForOne == exactInput);

        if (!ethIsSpecified) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        uint256 ethAmount = uint256(exactInput ? -params.amountSpecified : params.amountSpecified);
        uint256 fee = _quoteFee(key, ethAmount);
        if (fee == 0) return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);

        _accrue(Currency.unwrap(key.currency1), fee);
        poolManager.take(key.currency0, address(this), fee);

        return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(int128(uint128(fee)), 0), 0);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        bool exactInput = params.amountSpecified < 0;
        bool ethIsSpecified = (params.zeroForOne == exactInput);
        if (ethIsSpecified) return (BaseHook.afterSwap.selector, 0);

        int128 ethDelta = delta.amount0();
        if (ethDelta == 0) return (BaseHook.afterSwap.selector, 0);
        uint256 ethAmount = uint256(int256(ethDelta < 0 ? -ethDelta : ethDelta));

        uint256 fee = _quoteFee(key, ethAmount);
        if (fee == 0) return (BaseHook.afterSwap.selector, 0);

        _accrue(Currency.unwrap(key.currency1), fee);
        poolManager.take(key.currency0, address(this), fee);

        return (BaseHook.afterSwap.selector, int128(uint128(fee)));
    }

    // ── pull-based claims (always available, never pausable) ────────────────

    function claim() external returns (uint256 amount) {
        amount = ethOwed[msg.sender];
        if (amount == 0) revert NothingToClaim();
        ethOwed[msg.sender] = 0;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert EthTransferFailed();
        emit Claimed(msg.sender, amount);
    }

    // ── owner-tunable parameters (bounded by invariants) ────────────────────

    function setFeeTiers(Tier[] calldata tiers) external onlyOwner {
        _setFeeTiers(tiers);
    }

    function setSplit(uint16 protocolBps_, uint16 creatorBps_) external onlyOwner {
        _setSplit(protocolBps_, creatorBps_);
    }

    // ── creator-fee redirection ─────────────────────────────────────────────

    function setCreatorRecipientsAtLaunch(address token, CreatorRecipient[] calldata recipients) external {
        if (ILaunchTokenFactory(token).factory() != msg.sender) revert NotTokenFactory();
        if (creatorOf[token] == address(0)) revert CreatorNotRegistered();
        if (_creatorRecipients[token].length != 0) revert CreatorRecipientsAlreadySet();

        _writeCreatorRecipients(token, recipients);
        emit CreatorRecipientsSet(token, msg.sender, false, recipients);
    }

    function adminSetCreatorRecipients(address token, CreatorRecipient[] calldata recipients) external onlyOwner {
        if (creatorOf[token] == address(0)) revert CreatorNotRegistered();

        delete _creatorRecipients[token];
        if (recipients.length > 0) {
            _writeCreatorRecipients(token, recipients);
        }

        emit CreatorRecipientsSet(token, msg.sender, true, recipients);
    }

    // ── per-token custom base fee ───────────────────────────────────────────

    function setCustomFeesEnabled(bool enabled) external onlyOwner {
        customFeesEnabled = enabled;
        emit CustomFeesEnabledSet(enabled);
    }

    function setCustomFeeAtLaunch(address token, uint24 bps) external {
        if (ILaunchTokenFactory(token).factory() != msg.sender) revert NotTokenFactory();
        if (!customFeesEnabled) revert CustomFeesDisabled();
        if (creatorOf[token] == address(0)) revert CreatorNotRegistered();
        if (customFeeBps[token] != 0) revert CustomFeeAlreadySet();
        if (bps == 0 || bps < MIN_CUSTOM_FEE_BPS || bps > MAX_CUSTOM_FEE_BPS) {
            revert CustomFeeOutOfRange();
        }

        customFeeBps[token] = bps;
        emit CustomFeeSet(token, msg.sender, false, bps);
    }

    function adminSetCustomFee(address token, uint24 bps) external onlyOwner {
        if (creatorOf[token] == address(0)) revert CreatorNotRegistered();
        if (bps != 0) {
            if (!customFeesEnabled) revert CustomFeesDisabled();
            if (bps < MIN_CUSTOM_FEE_BPS || bps > MAX_CUSTOM_FEE_BPS) revert CustomFeeOutOfRange();
        }
        customFeeBps[token] = bps;
        emit CustomFeeSet(token, msg.sender, true, bps);
    }

    // ── partner registry & per-token attribution (NEW in v3) ────────────────

    /// @notice Register / update / remove a partner. Setting bps = 0 effectively
    ///         removes the partner — any tokens attributed to that wallet
    ///         immediately stop paying the partner cut on future swaps.
    ///         Already-accrued ethOwed balances are NEVER touched.
    ///
    ///         Partner bps is the partner's share of the PROTOCOL SLICE only.
    ///         The creator slice is never touched. e.g. with the default
    ///         protocol/creator split of 75/25 and a partnerBps of 4000:
    ///           - swapper pays X total fee
    ///           - creator gets   25% × X
    ///           - partner gets   40% × 75% × X  =  30% × X
    ///           - protocol gets  60% × 75% × X  =  45% × X
    function setPartnerBps(address partner, uint16 bps) external onlyOwner {
        if (partner == address(0)) revert ZeroAddress();
        if (bps > MAX_PARTNER_BPS) revert PartnerBpsExceedsMax();
        partnerBpsOf[partner] = bps;
        emit PartnerBpsSet(partner, bps);
    }

    /// @notice Attribute `token` to `partner` atomically at launch. ONE-TIME-WRITE
    ///         per token, callable only by the token's factory (the launchpad).
    ///         Pass address(0) to skip — the launchpad will simply not call
    ///         this function in that case.
    ///
    ///         Note: `partner` does NOT need to be currently registered as a
    ///         partner (partnerBpsOf[partner] may be 0 at this moment). If
    ///         not registered, no partner cut is taken until the admin calls
    ///         setPartnerBps() to register them. This lets attribution and
    ///         registration happen out of order.
    ///
    ///         Once set, only adminSetPartnerForToken() can change it.
    function setPartnerForTokenAtLaunch(address token, address partner) external {
        if (ILaunchTokenFactory(token).factory() != msg.sender) revert NotTokenFactory();
        if (creatorOf[token] == address(0)) revert CreatorNotRegistered();
        if (partnerOf[token] != address(0)) revert PartnerAlreadySet();
        if (partner == address(0)) revert ZeroAddress();

        partnerOf[token] = partner;
        emit PartnerForTokenSet(token, msg.sender, false, partner);
    }

    /// @notice Admin override: set / replace / clear the per-token partner
    ///         attribution for ANY token, at ANY time. Pass address(0) to
    ///         clear and revert that token to "no partner" (100% of protocol
    ///         slice → protocolWallet).
    ///
    ///         Already-accrued ethOwed balances are NEVER touched — this only
    ///         changes how FUTURE protocol-slice fees are routed for this token.
    function adminSetPartnerForToken(address token, address partner) external onlyOwner {
        if (creatorOf[token] == address(0)) revert CreatorNotRegistered();
        partnerOf[token] = partner; // address(0) is a valid "clear"
        emit PartnerForTokenSet(token, msg.sender, true, partner);
    }

    // ── extension module wiring (NEW in v3) ─────────────────────────────────

    /// @notice Hot-swap the extension module. Pass address(0) to disable.
    ///         No timelock — Safe owner can do this in one tx. The bound on
    ///         what the module can take (MAX_MODULE_BPS) is hardcoded, so
    ///         there's no path for even a malicious module to take more than
    ///         30% of the post-partner protocol slice.
    function setHookModule(address module) external onlyOwner {
        address old = hookModule;
        hookModule = module;
        emit HookModuleSet(old, module);
    }

    /// @notice Tune the gas budget given to the module per swap. Bounded so
    ///         no admin can grief swaps by setting an absurdly high or low
    ///         value (default 200k, hard ceiling 1M).
    function setModuleGasLimit(uint64 limit) external onlyOwner {
        if (limit == 0 || limit > MAX_MODULE_GAS) revert ModuleGasOutOfRange();
        moduleGasLimit = limit;
        emit ModuleGasLimitSet(limit);
    }

    function _writeCreatorRecipients(address token, CreatorRecipient[] calldata recipients) internal {
        uint256 n = recipients.length;
        if (n > MAX_CREATOR_RECIPIENTS) revert TooManyRecipients();

        uint256 sum;
        for (uint256 i = 0; i < n; i++) {
            if (recipients[i].wallet == address(0)) revert ZeroAddress();
            if (recipients[i].bps == 0) revert RecipientBpsZero();
            sum += recipients[i].bps;
            _creatorRecipients[token].push(recipients[i]);
        }
        if (sum != SPLIT_DENOM) revert RecipientBpsSumMismatch();
    }

    function _setFeeTiers(Tier[] memory tiers) internal {
        uint256 n = tiers.length;
        if (n == 0) revert TiersEmpty();
        if (n > MAX_TIERS) revert TooManyTiers();

        delete _feeTiers;
        for (uint256 i = 0; i < n; i++) {
            if (tiers[i].bps > MAX_FEE_BPS) revert TierBpsExceedsMax();
            if (i + 1 < n && tiers[i].maxMcapEth >= tiers[i + 1].maxMcapEth) revert TiersNotAscending();
            _feeTiers.push(tiers[i]);
        }

        emit FeeTiersUpdated(tiers);
    }

    function _setSplit(uint16 protocolBps_, uint16 creatorBps_) internal {
        if (uint256(protocolBps_) + uint256(creatorBps_) != SPLIT_DENOM) revert SplitDenomMismatch();
        if (creatorBps_ < MIN_CREATOR_BPS) revert CreatorBpsTooLow();
        protocolBps = protocolBps_;
        creatorBps = creatorBps_;
        emit SplitUpdated(protocolBps_, creatorBps_);
    }

    // ── views ───────────────────────────────────────────────────────────────

    function getFeeTiers() external view returns (Tier[] memory) {
        return _feeTiers;
    }

    function tierCount() external view returns (uint256) {
        return _feeTiers.length;
    }

    function getCreatorRecipients(address token) external view returns (CreatorRecipient[] memory) {
        return _creatorRecipients[token];
    }

    function creatorRecipientCount(address token) external view returns (uint256) {
        return _creatorRecipients[token].length;
    }

    function currentFeeBps(PoolKey calldata key) external view returns (uint24) {
        return _currentFeeBps(key);
    }

    function currentMcapEth(PoolKey calldata key) external view returns (uint256) {
        return _currentMcapEth(key);
    }

    function previewCustomFeeBps(uint24 baseBps, uint256 mcapWei) external pure returns (uint24) {
        if (baseBps == 0) return 0;
        return _applyCustomFeeDecay(baseBps, mcapWei);
    }

    /// @notice Convenience view: what would `token` pay out to the partner per
    ///         unit of protocol fee, in bps? Returns 0 if no partner is set or
    ///         the attributed partner is currently unregistered.
    function effectivePartnerBpsFor(address token) external view returns (uint16) {
        address partner = partnerOf[token];
        if (partner == address(0)) return 0;
        return partnerBpsOf[partner];
    }

    // ── internals ───────────────────────────────────────────────────────────

    function _accrue(address token, uint256 feeWei) internal {
        uint256 creatorCut = (feeWei * uint256(creatorBps)) / SPLIT_DENOM;
        uint256 protocolCut = feeWei - creatorCut;

        address creator = creatorOf[token];
        if (creator == address(0)) {
            // Pool attached this hook without going through a Launchpad — no
            // creator on file, so 100% of the fee accrues to the protocol so
            // nothing gets stuck. Partner attribution is also skipped here
            // because it requires creator registration.
            ethOwed[protocolWallet] += feeWei;
            emit FeeAccrued(token, feeWei, 0, feeWei);
            return;
        }

        // Partner cut is carved out of the PROTOCOL slice only (creator slice
        // is never touched). We look up partnerBpsOf at swap time, NOT at
        // attribution time, so admin-driven rate changes propagate to all
        // tokens currently attributed to that partner.
        uint256 partnerCut = 0;
        address partner = partnerOf[token];
        if (partner != address(0)) {
            uint16 pBps = partnerBpsOf[partner];
            if (pBps > 0) {
                // pBps is bounded by MAX_PARTNER_BPS (= 5000) at write-time,
                // so partnerCut is at most 50% of protocolCut.
                partnerCut = (protocolCut * uint256(pBps)) / SPLIT_DENOM;
                ethOwed[partner] += partnerCut;
                emit PartnerFeeAccrued(token, partner, partnerCut);
            }
        }

        // Remainder of the protocol slice (after partner cut).
        uint256 protocolNet = protocolCut - partnerCut;

        // Optional module call: routes a BOUNDED slice of protocolNet to a
        // recipient chosen by the module. Bounded by MAX_MODULE_BPS at the
        // contract level so even a malicious / buggy module can never take
        // more than 30% of the post-partner protocol slice. The call is
        // wrapped in try/catch with a gas budget, so a faulty module never
        // bricks swaps — it just gets skipped that swap.
        uint256 moduleCut = _maybeRunModule(token, creator, partner, feeWei, protocolNet);
        protocolNet -= moduleCut;

        ethOwed[protocolWallet] += protocolNet;

        // Creator-side distribution (unchanged from V2).
        CreatorRecipient[] storage recipients = _creatorRecipients[token];
        uint256 n = recipients.length;
        if (n == 0) {
            ethOwed[creator] += creatorCut;
        } else {
            uint256 distributed;
            for (uint256 i = 0; i + 1 < n; i++) {
                uint256 share = (creatorCut * uint256(recipients[i].bps)) / SPLIT_DENOM;
                ethOwed[recipients[i].wallet] += share;
                distributed += share;
            }
            ethOwed[recipients[n - 1].wallet] += creatorCut - distributed;
        }

        // FeeAccrued.protocolWei is the NET protocol amount (after partner cut),
        // matching the increment to ethOwed[protocolWallet]. Existing dashboards
        // that read just FeeAccrued continue to see what the protocol actually
        // received. The partner amount is reported separately via PartnerFeeAccrued.
        emit FeeAccrued(token, feeWei, creatorCut, protocolNet);
    }

    /// @dev Internal helper. Calls the extension module (if installed) with
    ///      try/catch and a bounded gas budget. Returns the actual amount
    ///      credited to the module recipient (always 0 if no module, the
    ///      call reverts, or the return is invalid).
    function _maybeRunModule(
        address token,
        address creator,
        address partner,
        uint256 feeWei,
        uint256 availableProtocolWei
    ) internal returns (uint256) {
        address moduleAddr = hookModule;
        if (moduleAddr == address(0) || availableProtocolWei == 0) return 0;

        uint256 maxCut = (availableProtocolWei * uint256(MAX_MODULE_BPS)) / SPLIT_DENOM;
        if (maxCut == 0) return 0;

        try IFeeHookModule(moduleAddr).onAccrue{gas: moduleGasLimit}(
            token, creator, partner, feeWei, maxCut
        ) returns (address recipient, uint256 cutWei) {
            if (recipient == address(0) || cutWei == 0) return 0;
            // Clamp to the cap. Modules that ask for more than maxCut are
            // bug-rate-limited rather than outright denied, which is more
            // forgiving to integrators.
            if (cutWei > maxCut) cutWei = maxCut;
            ethOwed[recipient] += cutWei;
            emit ModuleFeeAccrued(token, recipient, cutWei);
            return cutWei;
        } catch {
            // Module reverted / OOG / invalid return. Swap proceeds without
            // routing anything to the module — protocolWallet keeps the
            // would-have-been module slice. We emit so admin can detect bad
            // modules off-chain.
            emit ModuleCallFailed(token, moduleAddr);
            return 0;
        }
    }

    function _quoteFee(PoolKey calldata key, uint256 ethAmount) internal view returns (uint256) {
        uint24 bps = _currentFeeBps(key);
        return (ethAmount * bps) / SPLIT_DENOM;
    }

    function _currentFeeBps(PoolKey calldata key) internal view returns (uint24) {
        uint256 mcap = _currentMcapEth(key);

        if (customFeesEnabled) {
            uint24 customBase = customFeeBps[Currency.unwrap(key.currency1)];
            if (customBase != 0) return _applyCustomFeeDecay(customBase, mcap);
        }

        uint256 n = _feeTiers.length;
        for (uint256 i = 0; i + 1 < n; i++) {
            if (mcap < _feeTiers[i].maxMcapEth) return _feeTiers[i].bps;
        }
        return _feeTiers[n - 1].bps;
    }

    function _applyCustomFeeDecay(uint24 baseBps, uint256 mcapWei) internal pure returns (uint24) {
        uint256 reductions = mcapWei / CUSTOM_FEE_BAND_SIZE_WEI;
        if (reductions > CUSTOM_FEE_MAX_REDUCTIONS) reductions = CUSTOM_FEE_MAX_REDUCTIONS;
        if (reductions == 0) return baseBps;

        uint256 num = uint256(baseBps);
        uint256 den = 1;
        for (uint256 i = 0; i < reductions; i++) {
            num *= CUSTOM_FEE_RETAIN_BPS;
            den *= SPLIT_DENOM;
        }
        return uint24(num / den);
    }

    function _currentMcapEth(PoolKey calldata key) internal view returns (uint256) {
        PoolId pid = PoolId.wrap(keccak256(abi.encode(key)));
        (uint160 sqrtP,,,) = poolManager.getSlot0(pid);
        if (sqrtP == 0) return 0;

        uint256 q96 = 1 << 96;
        uint256 step1 = FullMath.mulDiv(TOTAL_SUPPLY, q96, uint256(sqrtP));
        return FullMath.mulDiv(step1, q96, uint256(sqrtP));
    }

    receive() external payable {}
}
