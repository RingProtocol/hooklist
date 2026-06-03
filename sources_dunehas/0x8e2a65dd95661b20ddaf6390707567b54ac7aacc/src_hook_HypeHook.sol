// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {HypeToken} from "../token/HypeToken.sol";
import {IHypeStaking} from "../staking/HypeStaking.sol";
import {HypeCurve} from "../library/HypeCurve.sol";
import {HypeTypes} from "../HypeTypes.sol";
import {HypeLib} from "../library/HypeLib.sol";
import {HypeLong} from "../library/HypeLong.sol";
import {HypeShort} from "../library/HypeShort.sol";
import {HypeReserve} from "../library/HypeReserve.sol";

/// @title  HypeHook — full perp (longs + shorts) on a bonding curve.
/// @notice Thin: holds all state, the v4 callbacks, user entry points, and
///         routes the heavy work to external delegate-libraries (kept under
///         EIP-170). See PERP_DESIGN.md for the complete spec.
contract HypeHook is IHooks, IUnlockCallback {
    using StateLibrary for IPoolManager;
    using HypeLib for HypeTypes.HypeState;

    // ─── Constants (PERP_DESIGN §11) ────────────────────────────────────────
    uint16  public constant MAX_LEVERAGE           = 3;
    uint256 public constant LONG_CAP_BPS           = 4000;   // 40% per-band ETH borrow
    uint256 public constant SHORT_CAP_BPS          = 2500;   // 25% per-band TOKEN borrow
    uint256 public constant BORROW_FEE_BPS         = 100;    // 1% at open
    uint256 public constant SWAP_FEE_BPS           = 100;    // 1% spot, external only
    uint256 public constant CLOSE_FEE_BPS          = 100;    // 1% on profit
    uint256 public constant LIQUIDATION_HEALTH_BPS = 10_500; // 105%
    uint256 public constant MIN_COLLATERAL_VALUE   = 0.01 ether;
    uint256 public constant CLOSE_COOLDOWN_BLOCKS  = 2;
    uint256 public constant NUM_INITIAL_BANDS      = 300;
    uint256 public constant MAX_BORROW_BANDS       = 5;
    uint16  public constant MAX_LIQS_PER_SWAP      = 10;
    uint16  public constant MAX_SCAN_PER_SWAP      = 64;
    uint16  public constant MAX_LIQS_PER_BLOCK     = 5;
    uint32  public constant TWAP_SECONDS           = 300;
    uint256 public constant MAX_BORROW_PER_BLOCK   = 5 ether;
    uint256 public constant BAD_DEBT_THRESHOLD     = 5 ether;
    uint256 public constant INSURANCE_BPS_HIGH     = 7000;
    uint256 public constant INSURANCE_BPS_LOW      = 5000;

    /// @dev Hardcoded LP-fee recipient (owner). No setter — v1 parity.
    address internal constant feeRecipient = 0x98Fb2387eb8B5db1811D6789DE8c1e12546d994D;

    // ─── Errors ─────────────────────────────────────────────────────────────
    error NotOwner();
    error PoolMgrOnly();
    error PoolAlreadyInitialized();
    error PoolNotInitializedErr();
    error UnauthorizedLP();
    error ZeroAddress();
    error Reentrancy();
    error InvalidAction();
    error EthTransferFailed();
    error TokenSupplyMismatch();
    error InvalidPoolKey();
    error CollateralBelowMin();
    error InvalidLeverage();
    error NoOpenPosition();
    error NotPositionOwner();
    error CooldownActive();
    error InsufficientBorrowCapacity();
    error BandAlreadySeeded();
    error UnauthorizedInit();
    error InvalidInitPrice();
    error ExactOutputDisallowed();
    error SlippageExceeded();
    error DeadlineExceeded();
    error NothingToClaim();
    error InvalidSellBps();
    error NothingSold();
    error PartialFill();
    error TradingNotEnabled();
    error ProtocolPaused();
    error BadSeedRange();
    error TokenTransferFailed();
    error StakingNotSet();
    error StakingAlreadySet();
    error TwapNotWarm();
    error BorrowCapPerBlockExceeded();
    error NotShortable();

    // ─── Immutables + the single state blob ─────────────────────────────────
    IPoolManager  public immutable poolManager;
    HypeToken     public immutable token;
    address       public immutable owner;
    IHypeStaking  public staking;
    bool          public stakingSet;

    HypeTypes.HypeState internal _s;

    uint256 private _locked = 1;
    modifier nonReentrant() {
        if (_locked != 1) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }
    modifier onlyOwner()       { if (msg.sender != owner) revert NotOwner(); _; }
    modifier onlyPoolManager() { if (msg.sender != address(poolManager)) revert PoolMgrOnly(); _; }

    event PositionOpened(uint256 indexed id, address indexed owner, HypeTypes.Side side, uint256 collateral, uint256 debt, uint256 holding);
    event PositionClosed(uint256 indexed id, address indexed owner, uint256 returned);
    event PositionLiquidated(uint256 indexed id, address indexed owner, HypeTypes.Side side);
    event BandSeeded(uint256 indexed bandId, int24 tickLower, int24 tickUpper, uint128 liquidity);
    event StakingSet(address indexed staking);
    event PausedSet(bool paused);
    event Claimed(address indexed user, uint256 amount);
    event ReserveRebalanced(bool soldToken, uint256 amountIn, uint256 amountOut);
    event BackstopWithdrawn(uint256 ethAmount, uint256 tokAmount);

    constructor(IPoolManager pm_, HypeToken token_, address owner_) {
        if (address(pm_) == address(0) || address(token_) == address(0) || owner_ == address(0)) {
            revert ZeroAddress();
        }
        poolManager = pm_;
        token = token_;
        owner = owner_;
        _s.nextPositionId = 1;
        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
    }

    receive() external payable {}

    // ─── Owner ──────────────────────────────────────────────────────────────
    function setStaking(address staking_) external onlyOwner {
        if (stakingSet) revert StakingAlreadySet();
        if (staking_ == address(0)) revert ZeroAddress();
        staking = IHypeStaking(staking_);
        stakingSet = true;
        emit StakingSet(staking_);
    }

    /// @notice Emergency stop for NEW opens only. Spot, closes, liquidations,
    ///         and rebalanceReserve are never affected — users can always exit.
    function pause()   external onlyOwner { _s.paused = true;  emit PausedSet(true);  }
    function unpause() external onlyOwner { _s.paused = false; emit PausedSet(false); }

    /// @notice Owner-timed reserve cleanup. Swaps excess one-sided reserve
    ///         through the pool (no owner capital — pool is counterparty),
    ///         refills bands, clears bad debt. Owner picks direction + amount;
    ///         it moves spot, so use small chunks in favorable conditions.
    ///         `minOut` is the owner's slippage floor on the swap output —
    ///         set it (and/or submit privately) so MEV can't sandwich the heal.
    function rebalanceReserve(bool sellToken, uint256 amount, uint256 minOut) external onlyOwner nonReentrant {
        bytes memory ret = poolManager.unlock(
            abi.encode(HypeTypes.Action.REBALANCE, abi.encode(sellToken, amount, minOut))
        );
        (uint256 amtIn, uint256 amtOut) = abi.decode(ret, (uint256, uint256));
        emit ReserveRebalanced(sellToken, amtIn, amtOut);
    }

    /// @notice Owner withdrawal of the protocol backstop (reserve + insurance,
    ///         either/both assets in one call; pass 0 to skip a side). Pulls
    ///         reserve-first then insurance, and is HARD-CAPPED at the
    ///         reserve+insurance counters — it can never reach user `claimable`
    ///         or long `holdingTOKEN`. Counters drop by exactly the amount sent,
    ///         so INV4/INV5 solvency stays exact. Trusted-owner facility (see
    ///         PERP_DESIGN §5) — deliberately NOT trustless.
    function withdrawBackstop(uint256 ethAmount, uint256 tokAmount) external onlyOwner nonReentrant {
        if (ethAmount > 0) {
            uint256 cap = _s.reserveETH + _s.insuranceETH;
            if (ethAmount > cap) ethAmount = cap;
            uint256 fromRes = ethAmount < _s.reserveETH ? ethAmount : _s.reserveETH;
            _s.reserveETH   -= fromRes;
            _s.insuranceETH -= (ethAmount - fromRes);
            (bool ok,) = payable(owner).call{value: ethAmount}("");
            if (!ok) revert EthTransferFailed();
        }
        if (tokAmount > 0) {
            uint256 capT = _s.reserveTOKEN + _s.insuranceTOKEN;
            if (tokAmount > capT) tokAmount = capT;
            uint256 fromResT = tokAmount < _s.reserveTOKEN ? tokAmount : _s.reserveTOKEN;
            _s.reserveTOKEN   -= fromResT;
            _s.insuranceTOKEN -= (tokAmount - fromResT);
            if (!token.transfer(owner, tokAmount)) revert TokenTransferFailed();
        }
        emit BackstopWithdrawn(ethAmount, tokAmount);
    }

    function claim() external nonReentrant returns (uint256 amount) {
        amount = _s.claimable[msg.sender];
        if (amount == 0) revert NothingToClaim();
        _s.claimable[msg.sender] = 0;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) { _s.claimable[msg.sender] = amount; revert EthTransferFailed(); }
        emit Claimed(msg.sender, amount);
    }

    // ─── Pool setup ─────────────────────────────────────────────────────────
    function initializePool() external onlyOwner {
        if (_s.poolInitialized) revert PoolAlreadyInitialized();
        if (token.balanceOf(address(this)) != HypeCurve.TOTAL_SUPPLY) revert TokenSupplyMismatch();

        PoolKey memory key = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(address(token)),
            fee: 0,
            tickSpacing: HypeCurve.TICK_SPACING,
            hooks: IHooks(address(this))
        });
        _s.poolKey = key;

        (, int24 band0TickUpper) = HypeCurve.bandToV4Ticks(0);
        poolManager.initialize(key, TickMath.getSqrtPriceAtTick(band0TickUpper));
        _s.poolInitialized = true;
        _s.launchBlock = uint64(block.number);

        // Pre-seed TWAP ring so no manipulation window exists right after deploy.
        _s.seedTwap(band0TickUpper, TWAP_SECONDS + 60);
    }

    function seedBands(uint256 fromBand, uint256 toBand) external onlyOwner nonReentrant {
        if (!_s.poolInitialized) revert PoolNotInitializedErr();
        if (toBand > NUM_INITIAL_BANDS || fromBand >= toBand) revert BadSeedRange();
        poolManager.unlock(abi.encode(HypeTypes.Action.SEED_BANDS, abi.encode(fromBand, toBand)));
        _s.bandsSeededCount += (toBand - fromBand);
        if (!_s.tradingEnabled && _s.bandsSeededCount == NUM_INITIAL_BANDS) _s.tradingEnabled = true;
    }

    // ─── v4 callbacks ───────────────────────────────────────────────────────
    function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96)
        external view onlyPoolManager returns (bytes4)
    {
        if (sender != address(this)) revert UnauthorizedInit();
        if (Currency.unwrap(key.currency0) != address(0))    revert InvalidPoolKey();
        if (Currency.unwrap(key.currency1) != address(token)) revert InvalidPoolKey();
        if (key.fee != 0)                                    revert InvalidPoolKey();
        if (key.tickSpacing != HypeCurve.TICK_SPACING)       revert InvalidPoolKey();
        if (address(key.hooks) != address(this))             revert InvalidPoolKey();
        (, int24 expectedUpper) = HypeCurve.bandToV4Ticks(0);
        if (sqrtPriceX96 != TickMath.getSqrtPriceAtTick(expectedUpper)) revert InvalidInitPrice();
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(address sender, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external view onlyPoolManager returns (bytes4)
    {
        if (sender != address(this)) revert UnauthorizedLP();
        return IHooks.beforeAddLiquidity.selector;
    }

    function beforeRemoveLiquidity(address sender, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external view onlyPoolManager returns (bytes4)
    {
        if (sender != address(this)) revert UnauthorizedLP();
        return IHooks.beforeRemoveLiquidity.selector;
    }

    /// @notice 1% ETH fee on external BUYs (zeroForOne). Hook-internal swaps exempt.
    function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (sender == address(this)) return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        if (!_s.tradingEnabled) revert TradingNotEnabled();
        if (params.amountSpecified > 0) revert ExactOutputDisallowed();
        if (params.amountSpecified == type(int256).min) revert ExactOutputDisallowed();
        if (!params.zeroForOne) return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);

        uint256 amountIn = uint256(-params.amountSpecified);
        uint256 fee = (amountIn * SWAP_FEE_BPS) / 10000;
        if (fee == 0) return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        if (fee > uint256(uint128(type(int128).max))) revert ExactOutputDisallowed();

        poolManager.take(key.currency0, address(this), fee);
        _s.claimable[feeRecipient] += fee;
        return (IHooks.beforeSwap.selector, toBeforeSwapDelta(int128(int256(fee)), 0), 0);
    }

    /// @notice 1% ETH fee on external SELLs + the liquidation scan.
    function afterSwap(address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata)
        external onlyPoolManager returns (bytes4, int128)
    {
        if (sender == address(this)) return (IHooks.afterSwap.selector, 0);

        if (!_s.inLiquidation) {
            HypeLib.scanAndLiquidate(
                _s, poolManager, address(token), LIQUIDATION_HEALTH_BPS, TWAP_SECONDS,
                MAX_SCAN_PER_SWAP, MAX_LIQS_PER_SWAP, MAX_LIQS_PER_BLOCK, NUM_INITIAL_BANDS
            );
        }
        HypeLib.writeObservation(_s, poolManager, _poolId());

        if (params.zeroForOne)           return (IHooks.afterSwap.selector, 0);
        if (params.amountSpecified >= 0) return (IHooks.afterSwap.selector, 0);

        int128 ethOut = delta.amount0();
        if (ethOut <= 0) return (IHooks.afterSwap.selector, 0);
        uint256 fee = (uint256(uint128(ethOut)) * SWAP_FEE_BPS) / 10000;
        if (fee == 0) return (IHooks.afterSwap.selector, 0);

        poolManager.take(key.currency0, address(this), fee);
        _s.claimable[feeRecipient] += fee;
        return (IHooks.afterSwap.selector, int128(int256(fee)));
    }

    function afterAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata)
        external pure returns (bytes4, BalanceDelta) { revert InvalidAction(); }
    function afterRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata)
        external pure returns (bytes4, BalanceDelta) { revert InvalidAction(); }
    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) { revert InvalidAction(); }
    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)  external pure returns (bytes4) { revert InvalidAction(); }

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true, afterInitialize: false,
            beforeAddLiquidity: true, afterAddLiquidity: false,
            beforeRemoveLiquidity: true, afterRemoveLiquidity: false,
            beforeSwap: true, afterSwap: true,
            beforeDonate: false, afterDonate: false,
            beforeSwapReturnDelta: true, afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false, afterRemoveLiquidityReturnDelta: false
        });
    }

    // ─── User entry points ──────────────────────────────────────────────────
    function openLong(uint256 leverage, uint256 minHoldingOut, uint256 deadline)
        external payable nonReentrant returns (uint256 positionId, uint256 holdingOut)
    {
        if (block.timestamp > deadline) revert DeadlineExceeded();
        _preOpenChecks(leverage);
        uint256 collateral = msg.value;
        uint256 borrowEth  = collateral * (leverage - 1);
        uint256 borrowFee  = (borrowEth * BORROW_FEE_BPS) / 10_000;
        uint256 effectiveCol = collateral - borrowFee;
        (uint160 sqrtP,,,) = poolManager.getSlot0(_poolId());

        bytes memory ret = poolManager.unlock(abi.encode(
            HypeTypes.Action.OPEN_LONG,
            abi.encode(borrowEth, effectiveCol, borrowFee, msg.sender, leverage)
        ));
        (uint256 actualBorrowed, uint256 swapTokensOut) = abi.decode(ret, (uint256, uint256));
        if (swapTokensOut < minHoldingOut) revert SlippageExceeded();

        positionId = _s.nextPositionId++;
        _s.positions[positionId] = HypeTypes.Position({
            owner: msg.sender, side: HypeTypes.Side.LONG,
            collateralETH: effectiveCol, debtETH: actualBorrowed, debtTOKEN: 0,
            holdingTOKEN: swapTokensOut, heldETH: 0,
            openSqrtPriceX96: sqrtP, leverage: uint8(leverage),
            openedAtBlock: uint64(block.number), realizedOut: 0
        });
        _registerPosition(positionId, msg.sender);
        _s.totalDebtETH      += actualBorrowed;
        _s.totalHoldingTOKEN += swapTokensOut;
        holdingOut = swapTokensOut;
        emit PositionOpened(positionId, msg.sender, HypeTypes.Side.LONG, effectiveCol, actualBorrowed, swapTokensOut);
    }

    function openShort(uint256 leverage, uint256 minEthOut, uint256 deadline)
        external payable nonReentrant returns (uint256 positionId, uint256 heldEthOut)
    {
        if (block.timestamp > deadline) revert DeadlineExceeded();
        _preOpenChecks(leverage);
        uint256 collateral = msg.value;
        uint256 borrowValEth = collateral * (leverage - 1);
        uint256 borrowFee    = (borrowValEth * BORROW_FEE_BPS) / 10_000;
        uint256 effectiveCol = collateral - borrowFee;
        (uint160 sqrtP,,,) = poolManager.getSlot0(_poolId());

        bytes memory ret = poolManager.unlock(abi.encode(
            HypeTypes.Action.OPEN_SHORT,
            abi.encode(borrowValEth, effectiveCol, borrowFee, msg.sender, leverage)
        ));
        (uint256 actualBorrowedTok, uint256 heldEth) = abi.decode(ret, (uint256, uint256));
        if (heldEth < minEthOut) revert SlippageExceeded();

        positionId = _s.nextPositionId++;
        _s.positions[positionId] = HypeTypes.Position({
            owner: msg.sender, side: HypeTypes.Side.SHORT,
            collateralETH: effectiveCol, debtETH: 0, debtTOKEN: actualBorrowedTok,
            holdingTOKEN: 0, heldETH: heldEth,
            openSqrtPriceX96: sqrtP, leverage: uint8(leverage),
            openedAtBlock: uint64(block.number), realizedOut: 0
        });
        _registerPosition(positionId, msg.sender);
        _s.totalDebtTOKEN += actualBorrowedTok;
        _s.totalHeldETH   += heldEth;
        heldEthOut = heldEth;
        emit PositionOpened(positionId, msg.sender, HypeTypes.Side.SHORT, effectiveCol, actualBorrowedTok, heldEth);
    }

    function close(uint256 positionId, uint256 sellBps, uint256 minOut, uint256 deadline)
        external nonReentrant returns (uint256 returned, uint256 consumed)
    {
        if (block.timestamp > deadline) revert DeadlineExceeded();
        if (sellBps == 0 || sellBps > 10_000) revert InvalidSellBps();
        HypeTypes.Position storage p = _s.positions[positionId];
        if (p.owner == address(0)) revert NoOpenPosition();
        if (p.owner != msg.sender) revert NotPositionOwner();
        if (block.number < p.openedAtBlock + CLOSE_COOLDOWN_BLOCKS) revert CooldownActive();

        bytes memory ret = poolManager.unlock(abi.encode(
            HypeTypes.Action.CLOSE, abi.encode(positionId, sellBps, minOut)
        ));
        (returned, consumed) = abi.decode(ret, (uint256, uint256));
    }

    // ─── Unlock callback (routes to delegate-libraries) ─────────────────────
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        (HypeTypes.Action action, bytes memory payload) = abi.decode(data, (HypeTypes.Action, bytes));

        if (action == HypeTypes.Action.SEED_BANDS) {
            (uint256 f, uint256 t) = abi.decode(payload, (uint256, uint256));
            for (uint256 i = f; i < t; i++) {
                (int24 tl, int24 tu, uint128 liq) = HypeLib.seedSingleBand(_s, poolManager, address(token), i);
                emit BandSeeded(i, tl, tu, liq);
            }
            return "";
        }
        if (action == HypeTypes.Action.OPEN_LONG) {
            return HypeLong.openHandler(
                _s, poolManager, address(token), payload,
                _cfg(), address(staking)
            );
        }
        if (action == HypeTypes.Action.OPEN_SHORT) {
            return HypeShort.openHandler(
                _s, poolManager, address(token), payload,
                _cfg(), address(staking)
            );
        }
        if (action == HypeTypes.Action.CLOSE) {
            return _routeClose(payload);
        }
        if (action == HypeTypes.Action.REBALANCE) {
            (bool sellTok, uint256 amt, uint256 minOut) = abi.decode(payload, (bool, uint256, uint256));
            return HypeReserve.rebalanceHandler(_s, poolManager, address(token), sellTok, amt, minOut, NUM_INITIAL_BANDS);
        }
        revert InvalidAction();
    }

    function _routeClose(bytes memory payload) internal returns (bytes memory) {
        (uint256 positionId,,) = abi.decode(payload, (uint256, uint256, uint256));
        HypeTypes.Side side = _s.positions[positionId].side;
        if (side == HypeTypes.Side.LONG) {
            return HypeLong.closeHandler(_s, poolManager, address(token), payload, _cfg(), address(staking));
        }
        return HypeShort.closeHandler(_s, poolManager, address(token), payload, _cfg(), address(staking));
    }

    // ─── Internal helpers ───────────────────────────────────────────────────
    /// @dev Packs the fee/cap config the libs need (avoids long arg lists).
    function _cfg() internal pure returns (HypeTypes.Cfg memory) {
        return HypeTypes.Cfg({
            longCapBps: LONG_CAP_BPS, shortCapBps: SHORT_CAP_BPS,
            maxBorrowBands: MAX_BORROW_BANDS, numBands: NUM_INITIAL_BANDS,
            twapSeconds: TWAP_SECONDS, maxBorrowPerBlock: MAX_BORROW_PER_BLOCK,
            borrowFeeBps: BORROW_FEE_BPS, closeFeeBps: CLOSE_FEE_BPS,
            badDebtThreshold: BAD_DEBT_THRESHOLD,
            insuranceBpsHigh: INSURANCE_BPS_HIGH, insuranceBpsLow: INSURANCE_BPS_LOW,
            liqHealthBps: LIQUIDATION_HEALTH_BPS,
            maxLeverage: MAX_LEVERAGE
        });
    }

    function _preOpenChecks(uint256 leverage) internal view {
        if (!_s.poolInitialized) revert PoolNotInitializedErr();
        if (!_s.tradingEnabled) revert TradingNotEnabled();
        if (_s.paused) revert ProtocolPaused();
        if (!stakingSet) revert StakingNotSet();
        if (leverage < 2 || leverage > MAX_LEVERAGE) revert InvalidLeverage();
        if (msg.value < MIN_COLLATERAL_VALUE) revert CollateralBelowMin();
    }

    function _registerPosition(uint256 id, address user) internal {
        _s.userPosIndex[id] = _s.userPositions[user].length;
        _s.userPositions[user].push(id);
        _s.openIdIndex[id] = _s.openIds.length;
        _s.openIds.push(id);
    }

    function _poolId() internal view returns (PoolId) {
        return PoolIdLibrary.toId(_s.poolKey);
    }

    // ─── Minimal views (rich views live in HypeLens) ────────────────────────
    function poolKey() external view returns (PoolKey memory) { return _s.poolKey; }
    function poolInitialized() external view returns (bool) { return _s.poolInitialized; }
    function tradingEnabled() external view returns (bool) { return _s.tradingEnabled; }
    function paused() external view returns (bool) { return _s.paused; }
    function bandsSeededCount() external view returns (uint256) { return _s.bandsSeededCount; }
    function launchBlock() external view returns (uint64) { return _s.launchBlock; }
    function totalDebtETH() external view returns (uint256) { return _s.totalDebtETH; }
    function totalDebtTOKEN() external view returns (uint256) { return _s.totalDebtTOKEN; }
    function totalBadDebtETH() external view returns (uint256) { return _s.totalBadDebtETH; }
    function totalBadDebtTOKEN() external view returns (uint256) { return _s.totalBadDebtTOKEN; }
    function totalHoldingTOKEN() external view returns (uint256) { return _s.totalHoldingTOKEN; }
    function totalHeldETH() external view returns (uint256) { return _s.totalHeldETH; }
    function reserveETH() external view returns (uint256) { return _s.reserveETH; }
    function reserveTOKEN() external view returns (uint256) { return _s.reserveTOKEN; }
    function insuranceETH() external view returns (uint256) { return _s.insuranceETH; }
    function insuranceTOKEN() external view returns (uint256) { return _s.insuranceTOKEN; }
    function claimable(address u) external view returns (uint256) { return _s.claimable[u]; }
    function openIdsLength() external view returns (uint256) { return _s.openIds.length; }
    function openIdAt(uint256 i) external view returns (uint256) { return _s.openIds[i]; }
    function positions(uint256 id) external view returns (HypeTypes.Position memory) { return _s.positions[id]; }
    function bands(uint256 id) external view returns (HypeTypes.Band memory) { return _s.bands[id]; }
    function userPositions(address u, uint256 i) external view returns (uint256) { return _s.userPositions[u][i]; }
    function userHistoryLength(address u) external view returns (uint256) { return _s.userHistory[u].length; }
    function userHistory(address u, uint256 i) external view returns (HypeTypes.ClosedPositionRecord memory) { return _s.userHistory[u][i]; }
    function getTwapTick(uint32 s) external view returns (int24 t, bool ok) { return HypeLib.twapTick(_s, s); }
    function currentSqrtPriceX96() external view returns (uint160 sp) { (sp,,,) = poolManager.getSlot0(_poolId()); }
}
