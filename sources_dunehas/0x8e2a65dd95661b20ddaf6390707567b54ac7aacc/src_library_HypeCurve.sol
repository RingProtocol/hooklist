// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

/// @title  HypeCurve — bonding-curve ↔ Uniswap v4 tick mapping.
/// @notice The bonding curve `realTokens × (V + eth) = K` is realized as N
///         v4 LP positions ("bands"). Band i covers cumulative pool ETH
///         [W·i, W·(i+1)] (W = TICK_WIDTH_ETH), seeded with the token slice the
///         curve sells across that ETH range. All math deterministic at deploy.
///         Pure-math library (no bytecode footprint — inlined).
library HypeCurve {
    uint256 internal constant TOTAL_SUPPLY = 1_000_000 ether; // 1M supply
    uint256 internal constant VIRTUAL_ETH  = 3.5 ether;       // virtual reserve V
    uint256 internal constant K            = (TOTAL_SUPPLY * VIRTUAL_ETH) / 1 ether; // 3.5e24
    uint256 internal constant TICK_WIDTH_ETH = 5 ether;       // 5-ETH bands
    int24   internal constant TICK_SPACING   = 60;

    error InvalidBand();

    /// @notice [ethLo, ethHi) cumulative-pool-ETH range covered by band `bandId`.
    function bandEthRange(uint256 bandId) internal pure returns (uint256 ethLo, uint256 ethHi) {
        ethLo = TICK_WIDTH_ETH * bandId;
        ethHi = TICK_WIDTH_ETH * (bandId + 1);
    }

    /// @notice Token allocation for band `bandId`:
    ///         alloc = K·1e18/(V+ethLo) − K·1e18/(V+ethHi). Σ over bands → TOTAL_SUPPLY.
    function loopAllocForBand(uint256 bandId) internal pure returns (uint256 alloc) {
        uint256 ethLo = TICK_WIDTH_ETH * bandId;
        uint256 ethHi = TICK_WIDTH_ETH * (bandId + 1);
        uint256 remainingLo = FullMath.mulDiv(K, 1e18, VIRTUAL_ETH + ethLo);
        uint256 remainingHi = FullMath.mulDiv(K, 1e18, VIRTUAL_ETH + ethHi);
        alloc = remainingLo - remainingHi;
    }

    /// @notice v4 sqrtPriceX96 at cumulative pool ETH `eth`.
    ///         v4Price = K·1e18/(V+eth)² ⟹ sqrtPriceX96 = sqrt(K·1e18)·2^96/(V+eth).
    function sqrtPriceX96AtEth(uint256 eth) internal pure returns (uint160 sqrtPriceX96) {
        uint256 result = FullMath.mulDiv(sqrt(K * 1e18), 1 << 96, VIRTUAL_ETH + eth);
        require(result <= type(uint160).max, "sqrtPriceOverflow");
        sqrtPriceX96 = uint160(result);
    }

    /// @notice v4 tick range for band `bandId`. Higher pool ETH → lower v4 price
    ///         → lower tick, so tickLower = tick(ethHi), tickUpper = tick(ethLo).
    function bandToV4Ticks(uint256 bandId) internal pure returns (int24 tickLower, int24 tickUpper) {
        (uint256 ethLo, uint256 ethHi) = bandEthRange(bandId);
        int24 tickHi = TickMath.getTickAtSqrtPrice(sqrtPriceX96AtEth(ethLo));
        int24 tickLo = TickMath.getTickAtSqrtPrice(sqrtPriceX96AtEth(ethHi));
        tickLower = _alignDown(tickLo, TICK_SPACING);
        tickUpper = _alignUp(tickHi, TICK_SPACING);
        if (tickLower >= tickUpper) revert InvalidBand();
    }

    /// @notice L to deposit `tokenAmount` token1 single-sided (current ≤ tickLower).
    function liquidityForLoopOnly(int24 tickLower, int24 tickUpper, uint256 tokenAmount)
        internal pure returns (uint128 liquidity)
    {
        return LiquidityAmounts.getLiquidityForAmount1(
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            tokenAmount
        );
    }

    /// @notice L to deposit `ethAmount` token0 single-sided (current ≤ tickLower).
    function liquidityForEthOnly(int24 tickLower, int24 tickUpper, uint256 ethAmount)
        internal pure returns (uint128 liquidity)
    {
        return LiquidityAmounts.getLiquidityForAmount0(
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            ethAmount
        );
    }

    /// @notice Inverse of sqrtPriceX96AtEth: cumulative pool ETH implied by a price.
    function ethAtSqrtPrice(uint160 sqrtPriceX96) internal pure returns (uint256 eth) {
        uint256 vPlusEth = FullMath.mulDiv(sqrt(K * 1e18), 1 << 96, sqrtPriceX96);
        eth = vPlusEth > VIRTUAL_ETH ? vPlusEth - VIRTUAL_ETH : 0;
    }

    /// @notice TOKEN value in ETH at a given sqrtPriceX96, overflow-safe.
    ///         ethValue = tokenAmount × (2^96/sqrtP)².
    function tokenValueInEth(uint256 tokenAmount, uint160 sqrtPriceX96) internal pure returns (uint256) {
        uint256 step1 = FullMath.mulDiv(tokenAmount, 1 << 96, uint256(sqrtPriceX96));
        return FullMath.mulDiv(step1, 1 << 96, uint256(sqrtPriceX96));
    }

    /// @notice Inverse: TOKEN amount whose value is `ethValue` at sqrtPriceX96.
    ///         token = ethValue × (sqrtP/2^96)².
    function ethValueToToken(uint256 ethValue, uint160 sqrtPriceX96) internal pure returns (uint256) {
        uint256 step1 = FullMath.mulDiv(ethValue, uint256(sqrtPriceX96), 1 << 96);
        return FullMath.mulDiv(step1, uint256(sqrtPriceX96), 1 << 96);
    }

    /// @dev Babylonian integer sqrt.
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
    }

    function _alignDown(int24 t, int24 spacing) private pure returns (int24) {
        int24 r = t % spacing;
        if (r < 0) r += spacing;
        return t - r;
    }

    function _alignUp(int24 t, int24 spacing) private pure returns (int24) {
        int24 down = _alignDown(t, spacing);
        return down == t ? t : down + spacing;
    }
}
