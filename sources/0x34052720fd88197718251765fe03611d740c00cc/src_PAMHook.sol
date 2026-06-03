// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BaseHook } from "@openzeppelin/uniswap-hooks/base/BaseHook.sol";

import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary,
    toBeforeSwapDelta
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";

import { IPAM } from "./interfaces/IPAM.sol";

/// @title PAMHook
/// @notice V4 combo hook — charges a PAM-side fee in ETH on **every** direction of the ETH/PAM
/// pool,
///         including exactOut paths so aggregators/bots cannot bypass the fee.
/// @dev ETH is `currency0` in the pool (address(0) always sorts first). The predicate
///         `ethIsSpecified = (zeroForOne == (amountSpecified < 0))` tells us which hook path collects:
///         - Buy exactIn  (zeroForOne=true,  amountSpecified<0): ETH specified   → `_beforeSwap` charges BUY_FEE_BPS
///         - Sell exactOut (zeroForOne=false, amountSpecified>0): ETH specified   → `_beforeSwap` charges
/// SELL_FEE_BPS
///         - Sell exactIn (zeroForOne=false, amountSpecified<0): ETH unspecified → `_afterSwap`  charges SELL_FEE_BPS
///         - Buy exactOut (zeroForOne=true,  amountSpecified>0): ETH unspecified → `_afterSwap`  charges BUY_FEE_BPS
///      Sign convention verified against v4-core `Hooks.sol` L270-280 (beforeSwap apply) and L305-313 (afterSwap
/// apply).
contract PAMHook is BaseHook {
    uint24 public constant BUY_FEE_BPS = 400;
    uint24 public constant SELL_FEE_BPS = 600;
    uint24 public constant BPS_DENOMINATOR = 10_000;
    uint24 public constant MAX_FEE_BPS = 1000;

    Currency public constant ETH = Currency.wrap(address(0));

    IPAM public immutable PAM_TOKEN;

    event FeeCollected(bool isBuy, bool isExactIn, uint256 ethAmount, address indexed swapper);

    error InvalidDelta();

    constructor(IPoolManager _poolManager, IPAM _pamToken) BaseHook(_poolManager) {
        PAM_TOKEN = _pamToken;
    }

    /// @dev `poolManager.take(ETH, address(this), amount)` performs a raw `call{value: amount}("")` to the
    ///      hook address — without a payable receive the transfer reverts with `NativeTransferFailed`.
    ///      The hook holds ETH only for the micro-window between `take` and the immediate forward
    ///      to `PAM_TOKEN.addFees`.
    receive() external payable { }

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

    /// @dev Fires on swaps where ETH is the *specified* currency: buy exactIn and sell exactOut. Other paths
    ///      fall through to `_afterSwap`. Sign: a positive `specified` delta subtracts from `amountSpecified`
    ///      exactly `feeAmount`, leaving the caller's settle matching the original input (see `Hooks.sol`
    ///      L270-280 for the `amountToSwap += hookDeltaSpecified` semantics).
    function _beforeSwap(address sender, PoolKey calldata, SwapParams calldata params, bytes calldata)
        internal
        virtual
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        bool isExactIn = params.amountSpecified < 0;
        bool ethIsSpecified = params.zeroForOne == isExactIn;

        if (!ethIsSpecified) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        uint256 ethAmount = isExactIn ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
        uint24 feeBps = params.zeroForOne ? BUY_FEE_BPS : SELL_FEE_BPS;
        uint256 feeAmount = (ethAmount * feeBps) / BPS_DENOMINATOR;
        if (feeAmount == 0) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        BeforeSwapDelta delta = toBeforeSwapDelta(int128(int256(feeAmount)), 0);
        poolManager.take(ETH, address(this), feeAmount);

        PAM_TOKEN.addFees{ value: feeAmount }();
        emit FeeCollected(params.zeroForOne, isExactIn, feeAmount, sender);

        return (BaseHook.beforeSwap.selector, delta, 0);
    }

    /// @dev Fires on swaps where ETH is the *unspecified* currency: sell exactIn and buy exactOut.
    ///      Read the actual settled ETH amount from `delta.amount0()` (positive when the pool pays the user,
    ///      negative when the user pays the pool) and take a percentage as fee. The returned `int128` is
    ///      added to `hookDeltaUnspecified` and applied as `swapDelta -= hookDelta` (Hooks.sol L305-313):
    ///      a positive return docks the fee from the caller's ETH side regardless of whether the caller
    ///      was paying or receiving ETH.
    function _afterSwap(
        address sender,
        PoolKey calldata,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal virtual override returns (bytes4, int128) {
        bool isExactIn = params.amountSpecified < 0;
        bool ethIsUnspecified = params.zeroForOne != isExactIn;

        if (!ethIsUnspecified) {
            return (BaseHook.afterSwap.selector, 0);
        }

        int128 ethDelta = delta.amount0();
        if (ethDelta == 0) revert InvalidDelta();

        // Cast via int256 before negation so `-int128.min` doesn't overflow.
        uint256 ethAmount = ethDelta > 0 ? uint256(int256(ethDelta)) : uint256(-int256(ethDelta));
        uint24 feeBps = params.zeroForOne ? BUY_FEE_BPS : SELL_FEE_BPS;
        uint256 feeAmount = (ethAmount * feeBps) / BPS_DENOMINATOR;
        if (feeAmount == 0) {
            return (BaseHook.afterSwap.selector, 0);
        }

        poolManager.take(ETH, address(this), feeAmount);
        PAM_TOKEN.addFees{ value: feeAmount }();
        emit FeeCollected(params.zeroForOne, isExactIn, feeAmount, sender);

        return (BaseHook.afterSwap.selector, int128(int256(feeAmount)));
    }
}
