// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

/// @notice Read-only quoter for live pool price + first-order swap quotes.
contract UoreQuoter {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager public immutable poolManager;
    PoolKey public canonicalKey;
    PoolId public immutable poolId;

    uint256 public constant TAX_BPS = 100;
    uint256 public constant BPS = 10_000;

    constructor(IPoolManager pm, PoolKey memory key) {
        poolManager = pm;
        canonicalKey = key;
        poolId = key.toId();
    }

    function currentSqrtPriceX96() public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
    }

    /// @notice price as currency1/currency0 scaled by 1e18.
    function currentPrice() external view returns (uint256) {
        uint256 sqrtP = uint256(currentSqrtPriceX96());
        if (sqrtP == 0) return 0;
        uint256 sqrtSquared = sqrtP * sqrtP;
        return ((sqrtSquared >> 96) * 1e18) >> 96;
    }

    /// @notice Quote a buy: input ETH wei, output UORE wei (post 1% hook tax).
    function quoteBuy(uint256 ethIn) external view returns (uint256 uoreOut) {
        uint256 sqrtP = uint256(currentSqrtPriceX96());
        if (sqrtP == 0 || ethIn == 0) return 0;
        uint256 sqrtSquared = sqrtP * sqrtP;
        uint256 grossOut = (ethIn * (sqrtSquared >> 96)) >> 96;
        uoreOut = (grossOut * (BPS - TAX_BPS)) / BPS;
    }

    /// @notice Quote a sell: input UORE wei, output ETH wei (post 1% hook tax).
    function quoteSell(uint256 uoreIn) external view returns (uint256 ethOut) {
        uint256 sqrtP = uint256(currentSqrtPriceX96());
        if (sqrtP == 0 || uoreIn == 0) return 0;
        uint256 stage1 = (uoreIn << 96) / sqrtP;
        uint256 grossOut = (stage1 << 96) / sqrtP;
        ethOut = (grossOut * (BPS - TAX_BPS)) / BPS;
    }
}
