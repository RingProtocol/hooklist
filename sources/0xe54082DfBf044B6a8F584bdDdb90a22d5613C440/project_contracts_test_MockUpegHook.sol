// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import "../token/IStartableToken.sol";
import "../library/IRandomSeedProvider.sol";
import "../svg_generation/IImageParams.sol";

/// @dev Mock hook for tests (no address flag validation, no PoolManager guard).
contract MockUpegHook is IRandomSeedProvider, IImageParams {
    IStartableToken public token;
    address public poolAddress;

    uint256 _randomSeed;
    uint256 _randomCount;

    constructor(address poolAddress_, address tokenAddress_) {
        poolAddress = poolAddress_;
        token = IStartableToken(tokenAddress_);
        _randomSeed = block.timestamp;
    }

    function randomSeed() external view override returns (uint256) {
        return _randomSeed;
    }

    function getImageParams() external pure override returns (ImageParams memory) {
        return ImageParams({
            colorsCount: 12,
            backgroundColorsCount: 6,
            accessoriesCount: 8,
            bodyCount: 8,
            eyesCount: 8,
            hairCount: 8,
            hornCount: 8,
            legsFrontCount: 8,
            legsBackCount: 8,
            tailCount: 8,
            groundCount: 8,
            wingsCount: 8
        });
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external returns (bytes4, BalanceDelta) {
        if (!token.isStarted()) token.start(poolAddress);
        return (IHooks.afterAddLiquidity.selector, toBalanceDelta(0, 0));
    }

    function afterSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external returns (bytes4, int128) {
        _randomizeSeed();
        return (IHooks.afterSwap.selector, 0);
    }

    function _randomizeSeed() internal {
        _randomSeed = uint256(
            keccak256(
                abi.encodePacked(
                    ++_randomCount,
                    _randomSeed,
                    block.timestamp,
                    block.prevrandao,
                    block.number
                )
            )
        );
    }
}
