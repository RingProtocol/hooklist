// SPDX-License-Identifier: MIT
//
//   ████████╗██╗ ██████╗██╗  ██╗██████╗
//   ╚══██╔══╝██║██╔════╝██║ ██╔╝██╔══██╗
//      ██║   ██║██║     █████╔╝ ██████╔╝
//      ██║   ██║██║     ██╔═██╗ ██╔══██╗
//      ██║   ██║╚██████╗██║  ██╗██║  ██║
//      ╚═╝   ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝
//
//   Website: https://tickr.xyz
//   Twitter: https://x.com/tickrxyz
//
pragma solidity >=0.8.9;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

contract LaunchHook is BaseHook {
    using BalanceDeltaLibrary for BalanceDelta;

    address public factory;
    address public governor;

    uint256 public constant FEE_BPS = 200;          // 2.00% total fee on input
    uint256 public constant CREATOR_SHARE_BPS = 5000; // creator gets 50% of fee
    // platform gets the remainder (50% of fee)

    event FeeCollected(
        address indexed token,
        uint256 totalFee,
        uint256 creatorShare,
        uint256 platformShare
    );

    event FactorySet(address indexed factory);

    constructor(IPoolManager _poolManager, address _governor) BaseHook(_poolManager) {
        require(_governor != address(0), "Zero governor");
        governor = _governor;
    }

    // One-time bind: factory deploys after hook (chicken-and-egg). Once set, immutable.
    function setFactory(address _factory) external {
        require(msg.sender == governor, "Not governor");
        require(factory == address(0), "Already set");
        require(_factory != address(0), "Zero address");
        factory = _factory;
        emit FactorySet(_factory);
    }

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

    // ETH → Token (buy) — fee taken from ETH input via beforeSwap delta
    function _beforeSwap(
        address /* sender */,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata /* hookData */
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // Only ETH→Token (zeroForOne=true) handled here. Token→ETH goes through afterSwap.
        if (!params.zeroForOne) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        // V1: exact-input only. Exact-output (positive amountSpecified) skips.
        if (params.amountSpecified >= 0) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        uint256 amountIn = uint256(-params.amountSpecified);
        uint256 feeAmount = (amountIn * FEE_BPS) / 10000;
        if (feeAmount == 0) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // Pull fee from PoolManager. Native ETH lands on this contract via receive().
        poolManager.take(key.currency0, address(this), feeAmount);

        _distribute(key, feeAmount);

        // Tell pool: input is reduced by feeAmount on the specified (currency0) side.
        BeforeSwapDelta delta = toBeforeSwapDelta(int128(int256(feeAmount)), 0);
        return (BaseHook.beforeSwap.selector, delta, 0);
    }

    // Token → ETH (sell) — fee taken from ETH output via afterSwap delta
    function _afterSwap(
        address /* sender */,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata /* hookData */
    ) internal override returns (bytes4, int128) {
        // Only Token→ETH (zeroForOne=false) handled here.
        if (params.zeroForOne) {
            return (BaseHook.afterSwap.selector, 0);
        }
        // V1: exact-input only.
        if (params.amountSpecified >= 0) {
            return (BaseHook.afterSwap.selector, 0);
        }

        int128 ethOut = delta.amount0();
        if (ethOut <= 0) {
            return (BaseHook.afterSwap.selector, 0);
        }

        uint256 feeAmount = (uint256(uint128(ethOut)) * FEE_BPS) / 10000;
        if (feeAmount == 0) {
            return (BaseHook.afterSwap.selector, 0);
        }

        // Take fee from output ETH (currency0) and distribute creator/platform shares.
        poolManager.take(key.currency0, address(this), feeAmount);
        _distribute(key, feeAmount);

        return (BaseHook.afterSwap.selector, int128(int256(feeAmount)));
    }

    // Stateless dispatch: creator share → currency1 (token contract balance accumulates),
    // platform share → factory. Token contract's withdrawFees() flow surfaces creator share.
    function _distribute(PoolKey calldata key, uint256 feeAmount) internal {
        uint256 creatorAmount = (feeAmount * CREATOR_SHARE_BPS) / 10000;
        uint256 platformAmount = feeAmount - creatorAmount;

        address tokenAddress = Currency.unwrap(key.currency1);
        if (creatorAmount > 0) {
            (bool s1, ) = payable(tokenAddress).call{value: creatorAmount}("");
            require(s1, "Creator transfer failed");
        }

        if (platformAmount > 0 && factory != address(0)) {
            (bool s2, ) = payable(factory).call{value: platformAmount}("");
            require(s2, "Platform transfer failed");
        }

        emit FeeCollected(tokenAddress, feeAmount, creatorAmount, platformAmount);
    }

    // Required: poolManager.take with native ETH transfers via low-level call.
    receive() external payable {}
}
