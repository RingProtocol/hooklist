// flood.markets
pragma solidity ^0.8.26;

import {BaseHook} from "./BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPool as IAavePool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

contract FloodHook is BaseHook, ERC20, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;

    error NoLP();
    error NoDonate();
    error BadPoolKey();
    error UnknownPool();
    error AlreadyInitialized();
    error ZeroAmount();
    error ZeroOutput();
    error ExactOutUnsupported();
    error SellExceedsCap(uint256 requested, uint256 cap);
    error AaveShortReturn(uint256 expected, uint256 actual);
    error YReserveTooLow();
    error AmountTooLarge();

    event Buy(
        PoolId indexed pid,
        address indexed buyer,
        address asset,
        uint256 amountIn,
        uint256 amountOut,
        uint256 baseFee,
        uint256 mevFee
    );
    event Sell(
        PoolId indexed pid,
        address indexed seller,
        address asset,
        uint256 amountIn,
        uint256 amountOut,
        uint256 baseFee,
        uint256 mevFee
    );

    struct PoolState {
        address asset;
        address aToken;
        uint256 xV;
        uint256 yReserve;
    }

    uint256 public constant TOTAL_SUPPLY  = 50_000_000 * 1e18;
    uint256 public constant N_WETH        = 20_000_000 * 1e18;
    uint256 public constant N_USDC        = 15_000_000 * 1e18;
    uint256 public constant N_USDT        = 15_000_000 * 1e18;
    uint256 public constant XV_WETH       = 13333e16;        // 133.33 WETH
    uint256 public constant XV_USDC       = 300_000e6;       // 300,000 USDC
    uint256 public constant XV_USDT       = 300_000e6;       // 300,000 USDT
    uint256 public constant MIN_Y_RESERVE = 1e15;            // 0.001 FLOOD floor on yReserve
    uint16  public constant FEE_BPS       = 30;
    uint16  public constant BPS_DENOM     = 10_000;
    uint16  public constant MAX_TOTAL_BPS = 100;             // 1% absolute cap (base + MEV)
    int128  public constant DELTA_MAX     = type(int128).max;

    uint256 public constant PRIORITY_FLOOR = 1 gwei;
    uint256 public constant MAX_PRIORITY   = 10_000 gwei;
    uint256 public constant MEV_FEE_DENOM  = 1_000 gwei;

    IAavePool public immutable AAVE;
    address public immutable WETH;
    address public immutable USDC;
    address public immutable USDT;
    address public immutable AWETH;
    address public immutable AUSDC;
    address public immutable AUSDT;

    mapping(PoolId => PoolState) public pools;
    mapping(address => PoolId) public assetToPool;
    bool public initWETH;
    bool public initUSDC;
    bool public initUSDT;

    constructor(
        IPoolManager _pm,
        IAavePool _aave,
        address _weth,
        address _usdc,
        address _usdt,
        address _aweth,
        address _ausdc,
        address _ausdt
    ) BaseHook(_pm) ERC20("Flood", "FLOOD") {
        AAVE  = _aave;
        WETH  = _weth;
        USDC  = _usdc;
        USDT  = _usdt;
        AWETH = _aweth;
        AUSDC = _ausdc;
        AUSDT = _ausdt;

        _mint(address(this), TOTAL_SUPPLY);

        SafeERC20.forceApprove(IERC20(_weth), address(_aave), type(uint256).max);
        SafeERC20.forceApprove(IERC20(_usdc), address(_aave), type(uint256).max);
        SafeERC20.forceApprove(IERC20(_usdt), address(_aave), type(uint256).max);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize:                true,
            afterInitialize:                 false,
            beforeAddLiquidity:              true,
            afterAddLiquidity:               false,
            beforeRemoveLiquidity:           true,
            afterRemoveLiquidity:            false,
            beforeSwap:                      true,
            afterSwap:                       false,
            beforeDonate:                    true,
            afterDonate:                     false,
            beforeSwapReturnDelta:           true,
            afterSwapReturnDelta:            false,
            afterAddLiquidityReturnDelta:    false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeAddLiquidity(
        address, PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata, bytes calldata
    ) internal pure override returns (bytes4) { revert NoLP(); }

    function _beforeRemoveLiquidity(
        address, PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata, bytes calldata
    ) internal pure override returns (bytes4) { revert NoLP(); }

    function _beforeDonate(
        address, PoolKey calldata, uint256, uint256, bytes calldata
    ) internal pure override returns (bytes4) { revert NoDonate(); }

    function _beforeInitialize(
        address, PoolKey calldata key, uint160
    ) internal override returns (bytes4) {
        if (Currency.unwrap(key.currency1) != address(this))      revert BadPoolKey();
        if (key.fee != 0)                                         revert BadPoolKey();
        if (key.tickSpacing != 1)                                 revert BadPoolKey();
        if (address(key.hooks) != address(this))                  revert BadPoolKey();

        address asset = Currency.unwrap(key.currency0);
        PoolId pid = key.toId();

        if (asset == WETH) {
            if (initWETH) revert AlreadyInitialized();
            initWETH = true;
            pools[pid] = PoolState(WETH, AWETH, XV_WETH, N_WETH);
            assetToPool[WETH] = pid;
        } else if (asset == USDC) {
            if (initUSDC) revert AlreadyInitialized();
            initUSDC = true;
            pools[pid] = PoolState(USDC, AUSDC, XV_USDC, N_USDC);
            assetToPool[USDC] = pid;
        } else if (asset == USDT) {
            if (initUSDT) revert AlreadyInitialized();
            initUSDT = true;
            pools[pid] = PoolState(USDT, AUSDT, XV_USDT, N_USDT);
            assetToPool[USDT] = pid;
        } else {
            revert BadPoolKey();
        }

        return BaseHook.beforeInitialize.selector;
    }

    function _mevFee(uint256 swapAmount) internal view returns (uint256) {
        if (tx.gasprice <= block.basefee) return 0;
        uint256 priority = tx.gasprice - block.basefee;
        if (priority <= PRIORITY_FLOOR) return 0;
        uint256 capped = priority > MAX_PRIORITY ? MAX_PRIORITY : priority;
        return (swapAmount * (capped - PRIORITY_FLOOR)) / MEV_FEE_DENOM;
    }

    function _capFee(uint256 swapAmount, uint256 baseFee, uint256 mevFee)
        internal pure returns (uint256, uint256)
    {
        uint256 maxTotal = (swapAmount * MAX_TOTAL_BPS) / BPS_DENOM;
        uint256 total = baseFee + mevFee;
        if (total <= maxTotal) return (baseFee, mevFee);
        if (baseFee >= maxTotal) return (maxTotal, 0);
        return (baseFee, maxTotal - baseFee);
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) internal override nonReentrant returns (bytes4, BeforeSwapDelta, uint24) {
        if (params.amountSpecified == 0)     revert ZeroAmount();
        if (params.amountSpecified > 0)      revert ExactOutUnsupported();
        uint256 absAmt = uint256(-params.amountSpecified);

        PoolState storage P = pools[key.toId()];
        if (P.asset == address(0))           revert UnknownPool();

        uint256 rX = IERC20(P.aToken).balanceOf(address(this));
        uint256 xE = rX + P.xV;
        uint256 y  = P.yReserve;

        if (params.zeroForOne) return _swapBuy(key, P, absAmt, xE, y);
        else                   return _swapSell(key, P, absAmt, xE, y, rX);
    }

    function _swapBuy(
        PoolKey calldata key, PoolState storage P,
        uint256 dAsset, uint256 xE, uint256 y
    ) internal returns (bytes4, BeforeSwapDelta, uint24) {
        uint256 baseFee = (dAsset * FEE_BPS) / BPS_DENOM;
        uint256 mevFee  = _mevFee(dAsset);
        (baseFee, mevFee) = _capFee(dAsset, baseFee, mevFee);
        uint256 net = dAsset - baseFee - mevFee;

        uint256 dFLOOD = (y * net) / (xE + net);
        if (dFLOOD == 0)                         revert ZeroOutput();
        if (y - dFLOOD < MIN_Y_RESERVE)          revert YReserveTooLow();
        if (dAsset > uint256(int256(DELTA_MAX)) || dFLOOD > uint256(int256(DELTA_MAX)))
                                                  revert AmountTooLarge();

        P.yReserve = y - dFLOOD;

        poolManager.take(key.currency0, address(this), dAsset);
        AAVE.supply(P.asset, dAsset, address(this), 0);

        poolManager.sync(key.currency1);
        _transfer(address(this), address(poolManager), dFLOOD);
        poolManager.settle();

        emit Buy(key.toId(), tx.origin, P.asset, dAsset, dFLOOD, baseFee, mevFee);

        return (
            BaseHook.beforeSwap.selector,
            toBeforeSwapDelta(int128(int256(dAsset)), -int128(int256(dFLOOD))),
            0
        );
    }

    function _swapSell(
        PoolKey calldata key, PoolState storage P,
        uint256 dFLOOD, uint256 xE, uint256 y, uint256 rX
    ) internal returns (bytes4, BeforeSwapDelta, uint24) {
        uint256 gross = (xE * dFLOOD) / (y + dFLOOD);
        if (gross == 0)                         revert ZeroOutput();

        uint256 baseFee = (gross * FEE_BPS) / BPS_DENOM;
        uint256 mevFee  = _mevFee(gross);
        (baseFee, mevFee) = _capFee(gross, baseFee, mevFee);
        uint256 dAsset = gross - baseFee - mevFee;

        if (dAsset > rX)                        revert SellExceedsCap(dAsset, rX);
        if (dFLOOD > uint256(int256(DELTA_MAX)) || dAsset > uint256(int256(DELTA_MAX)))
                                                  revert AmountTooLarge();

        P.yReserve = y + dFLOOD;

        poolManager.take(key.currency1, address(this), dFLOOD);

        poolManager.sync(key.currency0);
        uint256 actual = AAVE.withdraw(P.asset, dAsset, address(poolManager));
        if (actual < dAsset)                    revert AaveShortReturn(dAsset, actual);
        poolManager.settle();

        emit Sell(key.toId(), tx.origin, P.asset, dFLOOD, dAsset, baseFee, mevFee);

        return (
            BaseHook.beforeSwap.selector,
            toBeforeSwapDelta(int128(int256(dFLOOD)), -int128(int256(dAsset))),
            0
        );
    }

    // ============== widget-friendly view functions ==============

    function poolView(address asset)
        external view
        returns (uint256 realX, uint256 xV, uint256 yReserve, address aToken)
    {
        PoolState storage P = pools[assetToPool[asset]];
        if (P.asset == address(0)) revert UnknownPool();
        realX = IERC20(P.aToken).balanceOf(address(this));
        xV = P.xV;
        yReserve = P.yReserve;
        aToken = P.aToken;
    }

    function quoteBuy(address asset, uint256 amountIn)
        external view
        returns (uint256 amountOut, uint256 baseFee)
    {
        PoolState storage P = pools[assetToPool[asset]];
        if (P.asset == address(0)) revert UnknownPool();
        uint256 rX = IERC20(P.aToken).balanceOf(address(this));
        uint256 xE = rX + P.xV;
        baseFee = (amountIn * FEE_BPS) / BPS_DENOM;
        uint256 net = amountIn - baseFee;
        amountOut = (P.yReserve * net) / (xE + net);
    }

    function quoteBuyAt(address asset, uint256 amountIn, uint256 priorityWei)
        external view
        returns (uint256 amountOut, uint256 baseFee, uint256 mevFee)
    {
        PoolState storage P = pools[assetToPool[asset]];
        if (P.asset == address(0)) revert UnknownPool();
        uint256 rX = IERC20(P.aToken).balanceOf(address(this));
        uint256 xE = rX + P.xV;
        baseFee = (amountIn * FEE_BPS) / BPS_DENOM;
        mevFee = _simulateMevFee(amountIn, priorityWei);
        (baseFee, mevFee) = _capFee(amountIn, baseFee, mevFee);
        uint256 net = amountIn - baseFee - mevFee;
        amountOut = (P.yReserve * net) / (xE + net);
    }

    function quoteSell(address asset, uint256 amountIn)
        external view
        returns (uint256 amountOut, uint256 baseFee)
    {
        PoolState storage P = pools[assetToPool[asset]];
        if (P.asset == address(0)) revert UnknownPool();
        uint256 rX = IERC20(P.aToken).balanceOf(address(this));
        uint256 xE = rX + P.xV;
        uint256 gross = (xE * amountIn) / (P.yReserve + amountIn);
        baseFee = (gross * FEE_BPS) / BPS_DENOM;
        amountOut = gross - baseFee;
    }

    function quoteSellAt(address asset, uint256 amountIn, uint256 priorityWei)
        external view
        returns (uint256 amountOut, uint256 baseFee, uint256 mevFee)
    {
        PoolState storage P = pools[assetToPool[asset]];
        if (P.asset == address(0)) revert UnknownPool();
        uint256 rX = IERC20(P.aToken).balanceOf(address(this));
        uint256 xE = rX + P.xV;
        uint256 gross = (xE * amountIn) / (P.yReserve + amountIn);
        baseFee = (gross * FEE_BPS) / BPS_DENOM;
        mevFee = _simulateMevFee(gross, priorityWei);
        (baseFee, mevFee) = _capFee(gross, baseFee, mevFee);
        amountOut = gross - baseFee - mevFee;
    }

    function _simulateMevFee(uint256 swapAmount, uint256 priorityWei)
        internal pure returns (uint256)
    {
        if (priorityWei <= PRIORITY_FLOOR) return 0;
        uint256 capped = priorityWei > MAX_PRIORITY ? MAX_PRIORITY : priorityWei;
        return (swapAmount * (capped - PRIORITY_FLOOR)) / MEV_FEE_DENOM;
    }

    /// @notice Worst-case sell capacity assuming the maximum total fee (base + AmAMM cap = 100 bps).
    ///         Widgets should display this as the safe upper bound; the actual cap at quote time
    ///         is computed by sellCapAt(asset, priorityWei).
    function sellCap(address asset) external view returns (uint256 dFLOODMax) {
        return _sellCapWithFeeBps(asset, MAX_TOTAL_BPS);
    }

    /// @notice Sell capacity for a given priority fee. Uses the effective fee bps that would
    ///         apply at execution time for that priority, post _capFee clamping.
    function sellCapAt(address asset, uint256 priorityWei)
        external view returns (uint256 dFLOODMax)
    {
        return _sellCapWithFeeBps(asset, _effectiveFeeBps(priorityWei));
    }

    function _effectiveFeeBps(uint256 priorityWei) internal pure returns (uint16) {
        if (priorityWei <= PRIORITY_FLOOR) return FEE_BPS;
        uint256 capped = priorityWei > MAX_PRIORITY ? MAX_PRIORITY : priorityWei;
        // mevFee/swap = (capped - floor) / MEV_FEE_DENOM, expressed in bps:
        // mevBps = (capped - floor) * BPS_DENOM / MEV_FEE_DENOM
        uint256 mevBps = ((capped - PRIORITY_FLOOR) * BPS_DENOM) / MEV_FEE_DENOM;
        uint256 totalBps = uint256(FEE_BPS) + mevBps;
        if (totalBps > MAX_TOTAL_BPS) totalBps = MAX_TOTAL_BPS;
        return uint16(totalBps);
    }

    function _sellCapWithFeeBps(address asset, uint16 feeBps)
        internal view returns (uint256 dFLOODMax)
    {
        PoolState storage P = pools[assetToPool[asset]];
        if (P.asset == address(0)) revert UnknownPool();
        uint256 rX = IERC20(P.aToken).balanceOf(address(this));
        uint256 yMax = P.yReserve > MIN_Y_RESERVE ? P.yReserve - MIN_Y_RESERVE : 0;

        // Solve for dFLOOD where dAsset == rX, given fee f:
        //   gross = xE * dFLOOD / (y + dFLOOD), dAsset = gross * (B - f) / B
        //   ⇒ dFLOOD_max = rX * y * B / (xV*(B - f) - rX*f)
        uint256 leftSide  = P.xV * (BPS_DENOM - feeBps);
        uint256 rightSide = rX * feeBps;
        if (leftSide <= rightSide) {
            dFLOODMax = yMax;
        } else {
            uint256 denomRaw = leftSide - rightSide;
            uint256 capped = (rX * P.yReserve * BPS_DENOM) / denomRaw;
            dFLOODMax = capped > yMax ? yMax : capped;
        }
    }
}
