// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {HookBase} from "./HookBase.sol";
import {SpinCurve} from "../lib/SpinCurve.sol";

abstract contract HookSwap is HookBase {
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function afterInitialize(address, PoolKey calldata key, uint160, int24) external onlyPoolManager returns (bytes4) {
        if (Currency.unwrap(key.currency0) != address(0)) revert InvalidPool();
        if (Currency.unwrap(key.currency1) != address(TOKEN)) revert InvalidPool();
        if (address(key.hooks) != address(this)) revert InvalidPool();
        return IHooks.afterInitialize.selector;
    }

    function beforeInitialize(address, PoolKey calldata, uint160) external onlyPoolManager returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4)
    {
        revert LiquidityAdditionsForbidden();
    }

    function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        onlyPoolManager
        whenNotPaused
        returns (bytes4 selector, BeforeSwapDelta delta, uint24 lpFeeOverride)
    {
        if (params.amountSpecified >= 0) revert ExactOutputUnsupported();
        if (Currency.unwrap(key.currency0) != address(0) || Currency.unwrap(key.currency1) != address(TOKEN)) {
            revert InvalidPool();
        }

        (uint256 minOut, uint256 maxIn, uint256 deadline) = _decodeHookData(hookData);
        if (deadline > 0 && block.timestamp > deadline) revert Expired();

        uint256 amountIn = uint256(-params.amountSpecified);

        if (params.zeroForOne) {
            return _executeBuy(sender, amountIn, minOut);
        } else {
            return _executeSell(sender, amountIn, maxIn, minOut);
        }
    }

    function afterSwap(
        address,
        PoolKey calldata,
        SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, int128) {
        if (params.zeroForOne) {
            // Buy: ETH -> SPIN
            // Hook receives ETH from router, gives SPIN to router
            uint256 ethIn = uint256(-params.amountSpecified);
            uint256 mintAmount = SpinCurve.mintFor(ethCumulative, ethIn);
            uint256 taxAmount = _calculateTax(mintAmount);
            uint256 afterTax = mintAmount - taxAmount;

            // Settle ETH: hook has +ethIn from hookDelta (pool owes hook)
            POOL_MANAGER.take(ETH_CURRENCY, address(this), ethIn);

            // Settle SPIN: hook has -afterTax from hookDelta (hook owes pool)
            POOL_MANAGER.sync(TOKEN_CURRENCY);
            TOKEN.transfer(address(POOL_MANAGER), afterTax);
            POOL_MANAGER.settleFor(address(this));

            ethCumulative += ethIn;
            emit EthCumulativeUpdated(ethCumulative);
        } else {
            // Sell: SPIN -> ETH
            // Hook receives SPIN from the swapper, pays ETH to the swapper.
            uint256 tokenIn = uint256(-params.amountSpecified);
            uint256 taxAmount = _calculateTax(tokenIn);
            uint256 afterTax = tokenIn - taxAmount;
            uint256 ethOut = SpinCurve.burnFor(SpinCurve.totalMinted(ethCumulative), afterTax);

            // Settle ETH: hook pays ethOut via native settle (more direct than sync+settleFor).
            POOL_MANAGER.settle{value: ethOut}();

            // Settle SPIN: take() offsets hookDelta SPIN=+tokenIn AND transfers actual
            // ERC20 tokens from PoolManager to the hook. Requires the router to have
            // pre-settled the swapper's SPIN input before calling swap().
            POOL_MANAGER.take(TOKEN_CURRENCY, address(this), tokenIn);

            // Burn afterTax to reduce totalSupply per bonding curve spec.
            // taxAmount stays in hook balance, matching lockPoolBalance increment.
            if (taxAmount > 0) {
                lockPoolBalance += taxAmount;
            }
            if (afterTax > 0) {
                TOKEN.burn(address(this), afterTax);
            }

            if (ethOut <= ethCumulative) {
                ethCumulative -= ethOut;
            } else {
                if (ethOut > SpinCurve.totalMinted(ethCumulative)) revert BondingCurveInconsistent();
                ethCumulative = 0;
            }
            emit EthCumulativeUpdated(ethCumulative);
            emit SpinSell(msg.sender, tokenIn, ethOut, taxAmount);
        }

        _tryCheckPhaseTransition();
        _tryRelease();
        return (IHooks.afterSwap.selector, 0);
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.afterDonate.selector;
    }

    function _decodeHookData(bytes calldata hookData)
        internal
        pure
        returns (uint256 minOut, uint256 maxIn, uint256 deadline)
    {
        if (hookData.length < 64) revert MissingSlippageParams();
        // Backward compatible: 64 bytes = (minOut, maxIn), 96 bytes = (minOut, maxIn, deadline)
        if (hookData.length >= 96) {
            (minOut, maxIn, deadline) = abi.decode(hookData, (uint256, uint256, uint256));
        } else {
            (minOut, maxIn) = abi.decode(hookData, (uint256, uint256));
        }
    }

    function _executeBuy(address swapper, uint256 ethIn, uint256 minOut)
        internal
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (ethIn == 0) revert ZeroAmount();
        if (!phaseTwoActivated && ethIn > MAX_BUY_PHASE_ONE) revert BuyAmountExceedsLimit();

        lastBuyBlock[swapper] = block.number;
        lastGlobalBuyBlock = block.number;

        uint256 mintAmount = SpinCurve.mintFor(ethCumulative, ethIn);
        uint256 taxAmount = _calculateTax(mintAmount);
        uint256 afterTax = mintAmount - taxAmount;

        if (minOut > 0 && afterTax < minOut) revert SlippageLimitExceeded();

        TOKEN.mint(address(this), mintAmount);

        if (taxAmount > 0) {
            lockPoolBalance += taxAmount;
        }

        emit SpinBuy(swapper, ethIn, afterTax, taxAmount);

        // deltaSpecified = +ethIn: cancels the input so internal swap is bypassed
        // deltaUnspecified = -afterTax: hook provides SPIN output to the swapper
        BeforeSwapDelta delta = toBeforeSwapDelta(
            int128(int256(ethIn)),
            -int128(int256(afterTax))
        );
        return (IHooks.beforeSwap.selector, delta, 0);
    }

    function _executeSell(address swapper, uint256 tokenIn, uint256 maxIn, uint256 minOut)
        internal
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (tokenIn == 0) revert ZeroAmount();
        if (maxIn > 0 && tokenIn > maxIn) revert SlippageLimitExceeded();

        uint256 lb = lastBuyBlock[swapper];
        if (lb != 0 && block.number - lb < COOLDOWN_BLOCKS) revert CooldownActive();
        if (block.number - lastGlobalBuyBlock < COOLDOWN_BLOCKS) revert CooldownActive();

        uint256 taxAmount = _calculateTax(tokenIn);
        uint256 afterTax = tokenIn - taxAmount;

        uint256 ethOut = SpinCurve.burnFor(SpinCurve.totalMinted(ethCumulative), afterTax);
        if (ethOut == 0) revert NoSupplyToSell();
        if (minOut > 0 && ethOut < minOut) revert SlippageLimitExceeded();

        // deltaSpecified = +tokenIn: cancels the input so internal swap is bypassed
        // deltaUnspecified = -ethOut: hook provides ETH output to the swapper
        BeforeSwapDelta delta = toBeforeSwapDelta(
            int128(int256(tokenIn)),
            -int128(int256(ethOut))
        );
        return (IHooks.beforeSwap.selector, delta, 0);
    }

    function _calculateTax(uint256 amount) internal view returns (uint256) {
        uint256 taxRate = phaseTwoActivated ? PHASE_TWO_TAX : PHASE_ONE_TAX;
        return (amount * taxRate) / TAX_DENOMINATOR;
    }
}
