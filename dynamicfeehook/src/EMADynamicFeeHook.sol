// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

/// @title EMA Dynamic Fee Hook v2
/// @notice Swap fee scales with EMA price deviation. 30-step schedule, dense at low fees.
///         Anti-JIT 300 blocks via tx.origin. No owner, no admin, no hook fee.
contract EMADynamicFeeHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    uint256 private constant ALPHA_NUM = 8;
    uint256 private constant ALPHA_DENOM = 100;
    uint24 private constant MIN_FEE = 100;      // 0.01%
    uint24 private constant MAX_FEE = 30000;    // 3.00%
    uint256 public constant ANTI_JIT_BLOCKS = 300;

    mapping(PoolId => uint160) public emaSqrtPrice;
    mapping(PoolId => mapping(address => uint256)) public liquidityAddedBlock;

    event SwapFeeUpdated(PoolId indexed poolId, uint24 fee, uint256 deltaBps, uint160 newEma);

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ── afterInitialize: seed EMA ───────────────────────────────
    function _afterInitialize(address, PoolKey calldata key, uint160 sqrtPriceX96, int24)
        internal override returns (bytes4)
    {
        emaSqrtPrice[key.toId()] = sqrtPriceX96;
        return BaseHook.afterInitialize.selector;
    }

    // ── beforeSwap: calculate fee from EMA delta ────────────────
    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        internal override returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        uint160 ema = emaSqrtPrice[poolId];
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        if (ema == 0) {
            emaSqrtPrice[poolId] = sqrtPriceX96;
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, MIN_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG);
        }

        uint256 diff = sqrtPriceX96 >= ema ? uint256(sqrtPriceX96 - ema) : uint256(ema - sqrtPriceX96);
        uint256 deltaBps = diff * 10000 / uint256(ema);
        if (deltaBps > 10000) deltaBps = 10000;

        uint24 fee = _lookupFee(deltaBps);
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    // ── afterSwap: update EMA, emit event ───────────────────────
    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        internal override returns (bytes4, int128)
    {
        PoolId poolId = key.toId();
        uint160 ema = emaSqrtPrice[poolId];
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        if (ema == 0) {
            emaSqrtPrice[poolId] = sqrtPriceX96;
            emit SwapFeeUpdated(poolId, MIN_FEE, 0, sqrtPriceX96);
            return (BaseHook.afterSwap.selector, 0);
        }

        // divide first to avoid uint160 overflow
        uint160 newEma = uint160(
            (uint256(sqrtPriceX96) / ALPHA_DENOM * ALPHA_NUM) +
            (uint256(ema) / ALPHA_DENOM * (ALPHA_DENOM - ALPHA_NUM))
        );
        emaSqrtPrice[poolId] = newEma;

        uint256 diff = sqrtPriceX96 >= newEma ? uint256(sqrtPriceX96 - newEma) : uint256(newEma - sqrtPriceX96);
        uint256 deltaBps = diff * 10000 / uint256(newEma);
        if (deltaBps > 10000) deltaBps = 10000;

        emit SwapFeeUpdated(poolId, _lookupFee(deltaBps), deltaBps, newEma);
        return (BaseHook.afterSwap.selector, 0);
    }

    // ── Anti-JIT (tx.origin = реальный кошелёк) ─────────────────
    function _beforeAddLiquidity(address, PoolKey calldata key, ModifyLiquidityParams calldata, bytes calldata)
        internal override returns (bytes4)
    {
        liquidityAddedBlock[key.toId()][tx.origin] = block.number;
        return BaseHook.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(address, PoolKey calldata key, ModifyLiquidityParams calldata, bytes calldata)
        internal view override returns (bytes4)
    {
        uint256 addedBlock = liquidityAddedBlock[key.toId()][tx.origin];
        require(addedBlock == 0 || block.number >= addedBlock + ANTI_JIT_BLOCKS, "anti-JIT cooldown");
        return BaseHook.beforeRemoveLiquidity.selector;
    }

    function _afterRemoveLiquidity(
        address, PoolKey calldata key, ModifyLiquidityParams calldata,
        BalanceDelta, BalanceDelta, bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        delete liquidityAddedBlock[key.toId()][tx.origin];
        return (BaseHook.afterRemoveLiquidity.selector, toBalanceDelta(0, 0));
    }

    // ── Fee schedule: 30 steps, headroom 35% in low zone ────────
    function _lookupFee(uint256 d) internal pure returns (uint24) {
        // ultra-low: 0.01%-0.12% (11 steps, h=35%)
        if (d < 1)  return 100;    // 0.010%
        if (d < 2)  return 130;    // 0.013%  h=35%
        if (d < 3)  return 195;    // 0.020%  h=35%
        if (d < 4)  return 260;    // 0.026%  h=35%
        if (d < 5)  return 325;    // 0.033%  h=35%
        if (d < 7)  return 455;    // 0.046%  h=35%
        if (d < 9)  return 585;    // 0.059%  h=35%
        if (d < 11) return 715;    // 0.072%  h=35%
        if (d < 13) return 845;    // 0.085%  h=35%
        if (d < 15) return 975;    // 0.098%  h=35%
        if (d < 18) return 1170;   // 0.117%  h=35%
        // low-mid: 0.14%-0.47% (9 steps, h=35%)
        if (d < 22) return 1430;   // 0.143%  h=35%
        if (d < 28) return 1820;   // 0.182%  h=35%
        if (d < 34) return 2210;   // 0.221%  h=35%
        if (d < 40) return 2600;   // 0.260%  h=35%
        if (d < 46) return 2990;   // 0.299%  h=35%
        if (d < 52) return 3380;   // 0.338%  h=35%
        if (d < 58) return 3770;   // 0.377%  h=35%
        if (d < 65) return 4225;   // 0.423%  h=35%
        if (d < 72) return 4680;   // 0.468%  h=35%
        // upper: 0.65%-3.00% (10 steps, h=26-32%)
        if (d < 90)  return 6500;  // 0.650%  h=28%
        if (d < 110) return 8000;  // 0.800%  h=27%
        if (d < 135) return 10000; // 1.000%  h=26%
        if (d < 165) return 12000; // 1.200%  h=27%
        if (d < 200) return 14500; // 1.450%  h=28%
        if (d < 240) return 17500; // 1.750%  h=27%
        if (d < 300) return 21000; // 2.100%  h=30%
        if (d < 380) return 26000; // 2.600%  h=32%
        return MAX_FEE;            // 3.000%
    }
}
