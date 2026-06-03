// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// ─── Vendored minimal V4 types ───
struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

type BeforeSwapDelta is int256;
type BalanceDelta is int256;

// Canonical V4 BeforeSwapDelta packer.
function toBeforeSwapDelta(int128 specified, int128 unspecified) pure returns (BeforeSwapDelta r) {
    assembly { r := or(shl(128, specified), and(sub(shl(128, 1), 1), unspecified)) }
}

// BalanceDelta accessors. Convention from v4-core: amount0 in high 128, amount1 in low 128.
function amount0(BalanceDelta d) pure returns (int128) { return int128(BalanceDelta.unwrap(d) >> 128); }
function amount1(BalanceDelta d) pure returns (int128) { return int128(BalanceDelta.unwrap(d)); }

interface IPoolManager {
    function take(address currency, address to, uint256 amount) external;
    function extsload(bytes32 slot) external view returns (bytes32);
}

/// @title HaloHook — phase-tax (Halo launch)
/// @notice Always takes a baseline tax in beforeSwap (when ETH is the specified
///         currency) or in afterSwap (when token is specified). Refunds extra
///         in afterSwap when buying in refund phases. Sells always taxed.
///           ≥ 95%  CROWN : buy -3% (3% tax + 6% refund), sell +6%
///           85–95% MID   : buy +3%, sell +3%
///           < 85%  RECOIL: buy -6% (3% tax + 9% refund), sell +12% (also marks new apex)
///
///         Plus an ignition-tax decay: starts at 30% on both buys + sells,
///         drops by 1% per minute for 30 minutes, then settles into the
///         phase-based rates above. Wallets in `inscribed` (set in the
///         constructor — typically the bundle wallets) bypass ignition and
///         use phase rates from block 0. Refunds are suppressed for any
///         non-inscribed wallet while ignition is above the 3% baseline.
///
///         Every wei of every taxed swap stays in the hook as refund budget.
///         There is no dev fee on swaps — the dev's only ETH lever is the
///         admin-gated `sweep` (break-glass for a dead token). Transfer tax
///         is also zero — the token has no transfer hook.
contract HaloHook {
    // ──────────────────────────────────────────────────────────────────
    // CONFIG (effective rates, in bps)
    // ──────────────────────────────────────────────────────────────────
    uint256 public constant BASE_BPS = 300;            // 3% baseline buy tax + mid sell tax
    uint256 public constant CROWN_SELL_BPS = 600;      // 6% sell tax in crown
    uint256 public constant RECOIL_SELL_BPS = 1200;    // 12% sell tax in recoil

    uint256 public constant CROWN_BONUS_BPS = 300;     // -3% effective at crown
    uint256 public constant RECOIL_BONUS_BPS = 600;    // -6% effective in recoil

    uint256 public constant CROWN_ZONE_BPS = 9500;     // ≥95% of apex = crown refund phase
    uint256 public constant RECOIL_ZONE_BPS = 8500;    // <85% of apex = recoil refund phase
    uint256 public constant RECOIL_TRIGGER_BPS = 8500; // 15% drop = Receded → apexATH ratchets

    uint256 public constant PER_BLOCK_REFUND_CAP_BPS = 500; // 5% of reservoir per block (shared)

    // Ignition-tax decay (anti-snipe): 30% on both directions at launch,
    // declines linearly by 1%/minute, hits 0 at 30 minutes.
    uint256 public constant IGNITION_START_BPS = 3000;
    uint256 public constant IGNITION_DECAY_PER_MIN = 100;

    // Flags: BEFORE_INITIALIZE (0x2000) | BEFORE_SWAP (0x80) | AFTER_SWAP (0x40)
    //      | BEFORE_SWAP_RETURNS_DELTA (0x08) | AFTER_SWAP_RETURNS_DELTA (0x04)
    // The AFTER_SWAP_RETURNS_DELTA bit is critical: without it, the int128
    // returned from afterSwap is ignored, so any take() inside afterSwap goes
    // unsettled and the swap reverts with CurrencyNotSettled().
    uint256 public constant REQUIRED_HOOK_BITS = 0x20CC;
    uint256 private constant V4_POOLS_SLOT = 6;

    // ──────────────────────────────────────────────────────────────────
    // Immutables
    // ──────────────────────────────────────────────────────────────────
    address public immutable poolManager;
    address public immutable token;
    /// Admin of the hook. Set once in the constructor — typically the deployer
    /// EOA. Gates `setSentinel` and `sweep`. Immutable; never changeable.
    address public immutable admin;
    address public immutable ignitor;
    uint256 public immutable dustEth;

    // ──────────────────────────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────────────────────────
    uint256 public genesis;
    // No dev fee. The hook holds only refund budget. Sole admin lever for
    // ETH-out is `sweep` (admin-gated break-glass).

    uint256 public spot;
    uint256 public highWater;
    uint256 public apexATH;
    uint256 public recoilCount;
    bytes32 public poolId;
    /// Precomputed `keccak256(abi.encode(poolId, V4_POOLS_SLOT))` so afterSwap
    /// reads the V4 pool's slot0 with a single SLOAD. Saves ~1500 gas per swap.
    bytes32 private _poolStateSlot;

    enum Phase { NONE, CROWN, MID, RECOIL }

    // Per-block refund budget tracking
    uint256 public blockStartReservoir;
    uint256 public lastRefundBlock;
    uint256 public refundedThisBlock;

    // Same-block buy/sell sentinel. Tracks per-EOA via tx.origin (right
    // granularity for sandwich detection). Inactive at deploy; toggleable.
    mapping(address => uint256) public lastBuyOf;
    bool public sentinelActive;

    // Defence-in-depth reentrancy guard for `sweep`. CEI ordering already
    // makes the call safe even if `admin` is a contract that re-enters.
    bool private _withdrawLock;

    // Ignition-exempt set (the "inscribed"). Bundle wallets passed in the
    // constructor bypass the ignition tax and stay refund-eligible from
    // block 0. Frozen at deploy — no setter.
    mapping(address => bool) public inscribed;

    // ──────────────────────────────────────────────────────────────────
    // Errors / Events
    // ──────────────────────────────────────────────────────────────────
    error OnlyPoolManager();
    error BadBits();
    error SentinelOn();
    error NotAdmin();
    error WrongPool();
    error WrongOrder();
    error WrongToken();
    error NotIgnitor();
    error AlreadyLit();
    error Locked();
    error ZeroAddress();
    error Empty();
    error ExceedsBalance();

    event Lit(uint256 timestamp);
    event Levied(address indexed swapper, address indexed sender, bool isBuy, uint256 ethAmount, int256 deltaAmount, int256 effectiveTaxBps);
    event Refunded(address indexed recipient, address indexed sender, uint256 ethIn, uint256 refundAmount);
    event RefundCapped(address indexed recipient, uint256 desired, uint256 paid, string reason);
    event RefundSkipped(address indexed recipient, uint256 ethIn, uint256 wantedRefund, string reason);
    event Receded(uint256 apexATH, uint256 recoilBottom);
    event Crowned(uint256 newPeak);
    event Swept(address indexed to, uint256 amount);
    event SentinelSet(bool active, uint256 blockNumber, uint256 timestamp);
    event Inscribed(address indexed wallet);

    constructor(
        address _poolManager,
        address _token,
        address _admin,
        address _ignitor,
        uint256 _dustEth,
        address[] memory _inscribed
    ) {
        if (uint160(address(this)) & 0x3FFF != REQUIRED_HOOK_BITS) revert BadBits();
        if (_admin == address(0)) revert ZeroAddress();
        if (_ignitor == address(0)) revert ZeroAddress();
        // Defence-in-depth: addresses passed in must be the EOA that signed
        // the deploy tx. Stops deploys where _admin or _ignitor is the
        // CREATE2 factory, a contract, or another EOA. tx.origin in a
        // constructor is the signer of the originating tx — even via CREATE2.
        if (_admin != tx.origin) revert NotAdmin();
        if (_ignitor != tx.origin) revert NotIgnitor();
        poolManager = _poolManager;
        token = _token;
        admin = _admin;
        ignitor = _ignitor;
        dustEth = _dustEth;
        for (uint256 i = 0; i < _inscribed.length; i++) {
            address w = _inscribed[i];
            if (w == address(0)) continue;
            inscribed[w] = true;
            emit Inscribed(w);
        }
    }

    receive() external payable {}

    // ──────────────────────────────────────────────────────────────────
    // V4 Hook callbacks
    // ──────────────────────────────────────────────────────────────────
    modifier onlyPoolManager() {
        if (msg.sender != poolManager) revert OnlyPoolManager();
        _;
    }

    function _keyHash(PoolKey calldata key) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks
        ));
    }

    /// @dev Decode the refund recipient from hookData. Accepts hookData of
    /// >= 32 bytes whose first 32 bytes encode a non-zero address. Anything
    /// shorter (or zero in the address slot) falls back to tx.origin. Uses
    /// calldataload + uint160 mask to avoid abi.decode's strict upper-bits
    /// check (which would brick swaps from routers passing non-address junk
    /// in hookData).
    function _decodeRecipient(bytes calldata hd, address fallbackAddr) internal pure returns (address) {
        if (hd.length >= 32) {
            bytes32 word;
            assembly { word := calldataload(hd.offset) }
            address r = address(uint160(uint256(word)));
            if (r != address(0)) return r;
        }
        return fallbackAddr;
    }

    function beforeInitialize(address, PoolKey calldata key, uint160 sqrtPriceX96)
        external
        onlyPoolManager
        returns (bytes4)
    {
        if (tx.origin != ignitor) revert NotIgnitor();
        if (genesis != 0) revert AlreadyLit();
        if (key.currency0 != address(0)) revert WrongOrder(); // native ETH must be currency0
        if (key.currency1 != token) revert WrongToken();

        genesis = block.timestamp;
        spot = _sqrtToPrice(sqrtPriceX96);
        highWater = spot;
        poolId = _keyHash(key);
        _poolStateSlot = keccak256(abi.encode(poolId, V4_POOLS_SLOT));
        emit Lit(block.timestamp);
        return this.beforeInitialize.selector;
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        if (_keyHash(key) != poolId) revert WrongPool();

        bool exactIn = params.amountSpecified < 0;
        bool ethIsSpecified = (exactIn == params.zeroForOne);
        bool isBuy = params.zeroForOne;

        // Sentinel: track buys, reject same-block sells from same EOA.
        if (sentinelActive) {
            if (!isBuy && lastBuyOf[tx.origin] == block.number) revert SentinelOn();
            if (isBuy) lastBuyOf[tx.origin] = block.number;
        }

        // Token-specified swaps (exactOut buy / exactIn sell): pass through.
        // afterSwap will tax via int128 hookDelta on the unspecified (ETH) side.
        if (!ethIsSpecified) {
            return (this.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
        }

        uint256 ethAmount = exactIn ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
        uint256 taxBps = isBuy ? _buyTax(tx.origin) : _sellTax(tx.origin);
        return _applyLevied(sender, ethAmount, isBuy, taxBps);
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4, int128) {
        if (_keyHash(key) != poolId) revert WrongPool();

        bool exactIn = params.amountSpecified < 0;
        bool ethIsSpecified = (exactIn == params.zeroForOne);
        bool isBuy = params.zeroForOne;

        int128 a0 = amount0(delta);
        uint256 ethAmount = a0 < 0 ? uint256(uint128(-a0)) : uint256(uint128(a0));

        int128 hookDelta = 0;

        // Token-specified path: tax via hookDelta on unspecified (ETH) side.
        if (!ethIsSpecified && ethAmount > 0) {
            uint256 taxBps = isBuy ? _buyTax(tx.origin) : _sellTax(tx.origin);
            uint256 feeAmount = (ethAmount * taxBps) / 10_000;
            if (feeAmount > 0) {
                IPoolManager(poolManager).take(address(0), address(this), feeAmount);
                emit Levied(tx.origin, sender, isBuy, ethAmount, int256(feeAmount), int256(taxBps));
                hookDelta = int128(uint128(feeAmount));
            }
        }

        // Refund — gated by _refundEligible so non-inscribed wallets do NOT
        // get a refund while ignition tax is still elevated.
        if (isBuy && ethAmount > 0 && _refundEligible(tx.origin)) {
            uint256 bonusBps = _refundBonusForBuy();
            if (bonusBps > 0) {
                uint256 grossEth;
                if (ethIsSpecified) {
                    grossEth = uint256(-params.amountSpecified);
                } else {
                    grossEth = ethAmount + uint256(uint128(hookDelta));
                }
                uint256 refundAmt = (grossEth * (BASE_BPS + bonusBps)) / 10_000;
                address recipient = _decodeRecipient(hookData, tx.origin);
                _refund(sender, recipient, grossEth, refundAmt);
            }
        }

        // Update spot + min-ratchet peak/recoil logic
        bytes32 raw = IPoolManager(poolManager).extsload(_poolStateSlot);
        uint160 currentSqrtPrice = uint160(uint256(raw));
        if (currentSqrtPrice > 0) {
            spot = _sqrtToPrice(currentSqrtPrice);
            _ratchet(ethAmount);
        }

        return (this.afterSwap.selector, hookDelta);
    }

    // ──────────────────────────────────────────────────────────────────
    // Tax / refund helpers
    // ──────────────────────────────────────────────────────────────────
    function _applyLevied(address sender, uint256 ethAmount, bool isBuy, uint256 taxBps)
        internal
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint256 feeAmount = (ethAmount * taxBps) / 10_000;
        if (feeAmount == 0) {
            emit Levied(tx.origin, sender, isBuy, ethAmount, 0, 0);
            return (this.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
        }
        IPoolManager(poolManager).take(address(0), address(this), feeAmount);

        emit Levied(tx.origin, sender, isBuy, ethAmount, int256(feeAmount), int256(taxBps));

        BeforeSwapDelta delta = toBeforeSwapDelta(int128(uint128(feeAmount)), int128(0));
        return (this.beforeSwap.selector, delta, 0);
    }

    /// Reservoir = entire hook balance. There is no dev fee — every wei of
    /// every taxed swap stays here as refund budget. The only ways ETH
    /// leaves: paid refund, or admin-gated `sweep` (break-glass).
    function _reservoir() internal view returns (uint256) {
        return address(this).balance;
    }

    function _refund(address sender, address recipient, uint256 ethAmount, uint256 desiredRefund) internal {
        if (desiredRefund == 0 || recipient == address(0)) return;
        if (recipient == address(this)) {
            emit RefundSkipped(recipient, ethAmount, desiredRefund, "self_recipient");
            return;
        }
        uint256 vault = _reservoir();

        if (block.number != lastRefundBlock) {
            lastRefundBlock = block.number;
            blockStartReservoir = vault;
            refundedThisBlock = 0;
        }
        uint256 blockCap = (blockStartReservoir * PER_BLOCK_REFUND_CAP_BPS) / 10_000;
        uint256 remaining = blockCap > refundedThisBlock ? blockCap - refundedThisBlock : 0;
        uint256 capped = desiredRefund > remaining ? remaining : desiredRefund;
        if (capped < desiredRefund && capped > 0) {
            emit RefundCapped(recipient, desiredRefund, capped, "per_block_cap");
        }

        if (capped == 0) {
            emit RefundSkipped(recipient, ethAmount, desiredRefund, "block_cap_exhausted");
            return;
        }
        if (vault < capped) {
            emit RefundSkipped(recipient, ethAmount, desiredRefund, "vault_empty");
            return;
        }

        refundedThisBlock += capped;
        (bool ok, ) = payable(recipient).call{value: capped, gas: 100_000}("");
        if (ok) {
            emit Refunded(recipient, sender, ethAmount, capped);
        } else {
            refundedThisBlock -= capped;
            emit RefundSkipped(recipient, ethAmount, desiredRefund, "transfer_failed");
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // Phase classification + ratchet
    // ──────────────────────────────────────────────────────────────────
    /// Phase is computed against the HIGHER of highWater and apexATH so that
    /// after a 15% retrace (which resets highWater to the recoil bottom) the
    /// phase still reflects distance from the historical apex.
    function _apex() internal view returns (uint256) {
        return apexATH > highWater ? apexATH : highWater;
    }

    function _classify(uint256 s) internal view returns (Phase) {
        uint256 ref = _apex();
        if (ref == 0 || s == 0) return Phase.NONE;
        uint256 crownLine = (ref * CROWN_ZONE_BPS) / 10_000;
        uint256 recoilLine = (ref * RECOIL_ZONE_BPS) / 10_000;
        if (s >= crownLine) return Phase.CROWN;
        if (s < recoilLine) return Phase.RECOIL;
        return Phase.MID;
    }

    function _isRecoil() internal view returns (bool) {
        return _classify(spot) == Phase.RECOIL;
    }

    function _refundBonusForBuy() internal view returns (uint256) {
        Phase p = _classify(spot);
        if (p == Phase.CROWN) return CROWN_BONUS_BPS;
        if (p == Phase.RECOIL) return RECOIL_BONUS_BPS;
        return 0;
    }

    /// Phase-based sell tax: crown 6%, recoil 12%, mid 3%.
    function _phaseSellBps() internal view returns (uint256) {
        Phase p = _classify(spot);
        if (p == Phase.RECOIL) return RECOIL_SELL_BPS;
        if (p == Phase.CROWN) return CROWN_SELL_BPS;
        return BASE_BPS;
    }

    /// Linearly decaying anti-snipe tax. Returns 3000 at the launch second,
    /// drops 100 bps every 60s, hits 0 at 1800s (30 min). Returns 0 before
    /// `genesis` is set.
    function ignitionBps() public view returns (uint256) {
        uint256 ts = genesis;
        if (ts == 0 || block.timestamp <= ts) return ts == 0 ? 0 : IGNITION_START_BPS;
        uint256 decay = ((block.timestamp - ts) / 60) * IGNITION_DECAY_PER_MIN;
        if (decay >= IGNITION_START_BPS) return 0;
        return IGNITION_START_BPS - decay;
    }

    /// Effective buy tax for `taxPayer` — `BASE_BPS` for inscribed wallets
    /// or once ignition has decayed below the baseline; otherwise ignition.
    function _buyTax(address taxPayer) internal view returns (uint256) {
        if (inscribed[taxPayer]) return BASE_BPS;
        uint256 lb = ignitionBps();
        return lb > BASE_BPS ? lb : BASE_BPS;
    }

    /// Effective sell tax — phase-based by default; raised to ignition tax
    /// for non-inscribed wallets while it's still above the phase rate.
    function _sellTax(address taxPayer) internal view returns (uint256) {
        uint256 phaseBps = _phaseSellBps();
        if (inscribed[taxPayer]) return phaseBps;
        uint256 lb = ignitionBps();
        return lb > phaseBps ? lb : phaseBps;
    }

    /// A wallet is refund-eligible iff it's inscribed or ignition has
    /// decayed to (or below) the baseline. Stops snipers from claiming
    /// refunds during the elevated-tax window.
    function _refundEligible(address taxPayer) internal view returns (bool) {
        if (inscribed[taxPayer]) return true;
        return ignitionBps() <= BASE_BPS;
    }

    /// Min-ratchet: only bump highWater / Receded on a meaningful swap.
    /// Symmetric guard on both sides.
    function _ratchet(uint256 swapEthAmount) internal {
        if (spot > highWater && swapEthAmount >= dustEth) {
            highWater = spot;
            emit Crowned(spot);
        }
        if (highWater > 0) {
            uint256 recoilThreshold = (highWater * RECOIL_TRIGGER_BPS) / 10_000;
            if (spot <= recoilThreshold && spot < highWater && swapEthAmount >= dustEth) {
                if (highWater > apexATH) {
                    apexATH = highWater;
                }
                emit Receded(apexATH, spot);
                highWater = spot;
                recoilCount++;
            }
        }
    }

    function _sqrtToPrice(uint160 sqrtPriceX96) internal pure returns (uint256) {
        uint256 sp = uint256(sqrtPriceX96);
        uint256 reduced = sp >> 48;
        uint256 sqr = reduced * reduced;
        if (sqr == 0) return 0;
        return (uint256(1) << 224) / sqr;
    }

    // ──────────────────────────────────────────────────────────────────
    // Admin / view
    // ──────────────────────────────────────────────────────────────────
    /// @notice EMERGENCY-ONLY: withdraw `amount` wei from the hook to `to`.
    /// Callable only by `admin`. The hook balance IS the refund vault —
    /// every wei pulled out is refund budget removed from the protocol, so
    /// this is the wind-down lever for a dead token, not a routine claim.
    ///
    /// Amount semantics:
    ///  - `amount == type(uint256).max`: sweep full balance.
    ///  - `amount == 0`: revert (`Empty`).
    ///  - `amount > balance`: revert (`ExceedsBalance`) — no clamping.
    ///  - otherwise: send exactly `amount`.
    ///
    /// Security: admin-gated, zero-address rejected, reentrancy-locked,
    /// admin is immutable.
    function sweep(address to, uint256 amount) external {
        if (msg.sender != admin) revert NotAdmin();
        if (to == address(0)) revert ZeroAddress();
        if (_withdrawLock) revert Locked();
        uint256 bal = address(this).balance;
        if (amount == type(uint256).max) amount = bal;
        if (amount == 0) revert Empty();
        if (amount > bal) revert ExceedsBalance();
        _withdrawLock = true;
        (bool ok, ) = payable(to).call{value: amount}("");
        require(ok, "transfer failed");
        _withdrawLock = false;
        emit Swept(to, amount);
    }

    /// @notice Toggle the same-block sentinel on or off. Admin only.
    /// Toggleable any time — flip off temporarily for a same-block bundle op
    /// (LP restock, MM sweep) then re-arm.
    function setSentinel(bool active) external {
        if (msg.sender != admin) revert NotAdmin();
        sentinelActive = active;
        emit SentinelSet(active, block.number, block.timestamp);
    }

    function reservoir() external view returns (uint256) {
        return _reservoir();
    }

    /// View: current effective buy rate for an inscribed wallet (or post-
    /// ignition). Negative = net refund.
    function buyBps() external view returns (int256) {
        Phase p = _classify(spot);
        if (p == Phase.CROWN) return -int256(CROWN_BONUS_BPS);
        if (p == Phase.RECOIL) return -int256(RECOIL_BONUS_BPS);
        return int256(BASE_BPS);
    }

    function sellBps() external view returns (int256) {
        return int256(_phaseSellBps());
    }

    function phase() external view returns (Phase) {
        return _classify(spot);
    }

    function apex() external view returns (uint256) {
        return _apex();
    }

    function snapshot() external view returns (
        uint256 _genesis,
        int256  _buyBps,
        int256  _sellBps,
        uint256 _spot,
        uint256 _highWater,
        uint256 _apexATH,
        uint256 _recoilCount,
        uint256 _reservoirEth,
        Phase   _phase,
        uint256 _apexRef,
        bool    _sentinelActive,
        uint256 _ignitionBps
    ) {
        Phase p = _classify(spot);
        int256 bbps;
        if (p == Phase.CROWN) bbps = -int256(CROWN_BONUS_BPS);
        else if (p == Phase.RECOIL) bbps = -int256(RECOIL_BONUS_BPS);
        else bbps = int256(BASE_BPS);
        int256 sbps = int256(_phaseSellBps());
        return (
            genesis, bbps, sbps, spot, highWater, apexATH,
            recoilCount, _reservoir(), p, _apex(),
            sentinelActive, ignitionBps()
        );
    }
}
