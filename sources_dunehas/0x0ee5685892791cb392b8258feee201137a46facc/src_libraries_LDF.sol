// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/*//////////////////////////////////////////////////////////////
                              lo0p
                    web · https://lo0p.io
                    x   · https://x.com/lo0pio
                    tg  · https://t.me/lo0pio
//////////////////////////////////////////////////////////////*/

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

/// @title LDF — Liquidity Distribution Function for lo0p V2
/// @notice Pure math library that maps lo0p's "30 ETH per band" model onto
///         Uniswap V4's tick infrastructure. Each lo0p band [30·i, 30·(i+1)] of
///         cumulative pool ETH corresponds to a specific V4 tick range, and is
///         allocated the LOOP slice the original constant-product curve
///         `K = (V + x) · realTokens` would have sold across that ETH band.
///
///         All math is deterministic at deploy time — band → V4 tick mapping is
///         fixed. The library is consumed by LendingHookV2 and the deploy
///         script.
library LDF {
    /// @dev   Pool constants — identical to V1.
    uint256 internal constant TOTAL_SUPPLY = 1_000_000 ether; // 1M LOOP
    uint256 internal constant VIRTUAL_ETH  = 20 ether;        // phantom 20 ETH for swap math
    uint256 internal constant K            = (TOTAL_SUPPLY * VIRTUAL_ETH) / 1 ether; // 20M (in 18-dec form)

    /// @dev   Band geometry.
    uint256 internal constant TICK_WIDTH_ETH = 30 ether;      // each band covers 30 ETH inflow

    /// @dev   V4 tickSpacing the hook uses. Must match poolKey.tickSpacing.
    int24   internal constant TICK_SPACING   = 60;

    error InvalidBand();

    /// @notice Pool ETH range covered by lo0p band `bandId`.
    /// @return ethLo lower bound (inclusive) in wei
    /// @return ethHi upper bound (exclusive) in wei
    function bandEthRange(uint256 bandId) internal pure returns (uint256 ethLo, uint256 ethHi) {
        ethLo = TICK_WIDTH_ETH * bandId;
        ethHi = TICK_WIDTH_ETH * (bandId + 1);
    }

    /// @notice Which lo0p band `eth` falls into.
    function ethToBandId(uint256 eth) internal pure returns (uint256) {
        return eth / TICK_WIDTH_ETH;
    }

    /// @notice LOOP token allocation for band `bandId` under the constant-product
    ///         slice formula:
    ///             LOOP_i = K/(V + 30·i)  −  K/(V + 30·(i+1))
    ///         Sum across all i = K/V = TOTAL_SUPPLY (matches initial supply).
    function loopAllocForBand(uint256 bandId) internal pure returns (uint256 loopAlloc) {
        uint256 ethLo = TICK_WIDTH_ETH * bandId;
        uint256 ethHi = TICK_WIDTH_ETH * (bandId + 1);
        // remaining(eth) [wei] = K · 1e18 / (V + eth)   — K is (1M * 20)/1e18 = 2e25
        // so remaining(0) = 2e25 · 1e18 / 2e19 = 1e24 wei = 1M LOOP ✓
        uint256 remainingLo = FullMath.mulDiv(K, 1e18, VIRTUAL_ETH + ethLo);
        uint256 remainingHi = FullMath.mulDiv(K, 1e18, VIRTUAL_ETH + ethHi);
        loopAlloc = remainingLo - remainingHi;
    }

    /// @notice Spot V4 price (LOOP per ETH × 2^96 sqrt) at a given pool ETH.
    ///         Matches the constant-product curve:
    ///             realTokens(eth) = K · 1e18 / (V + eth)
    ///             v4Price = realTokens / (V + eth) = K · 1e18 / (V + eth)²
    ///             sqrtPriceX96 = sqrt(v4Price) · 2^96
    function sqrtPriceX96AtEth(uint256 eth) internal pure returns (uint160 sqrtPriceX96) {
        uint256 denom = VIRTUAL_ETH + eth;             // wei
        // sqrt(K·1e18) · 2^96 / denom
        // K·1e18 ~ 2e25, sqrt = ~4.47e12, then ·2^96 fits in 160-bit easily
        uint256 sqrtKscaled = sqrt(K * 1e18);          // sqrt(2e25) ≈ 4.472e12
        // sqrtPriceX96 = sqrtKscaled · 2^96 / denom
        uint256 result = FullMath.mulDiv(sqrtKscaled, 1 << 96, denom);
        require(result <= type(uint160).max, "sqrtPriceOverflow");
        sqrtPriceX96 = uint160(result);
    }

    /// @notice V4 tick range for lo0p band `bandId`.
    ///         Higher pool ETH → lower V4 price → lower V4 tick. So:
    ///             V4 tickLower = tick at ethHi (lower price)
    ///             V4 tickUpper = tick at ethLo (higher price)
    /// @dev    Both ticks are aligned down to TICK_SPACING.
    function bandToV4Ticks(uint256 bandId) internal pure returns (int24 tickLower, int24 tickUpper) {
        (uint256 ethLo, uint256 ethHi) = bandEthRange(bandId);
        uint160 sqrtPHi = sqrtPriceX96AtEth(ethLo); // higher V4 price
        uint160 sqrtPLo = sqrtPriceX96AtEth(ethHi); // lower V4 price
        int24 tickHi = TickMath.getTickAtSqrtPrice(sqrtPHi);
        int24 tickLo = TickMath.getTickAtSqrtPrice(sqrtPLo);
        tickLower = _alignDown(tickLo, TICK_SPACING);
        tickUpper = _alignUp(tickHi, TICK_SPACING);
        if (tickLower >= tickUpper) revert InvalidBand();
    }

    /// @notice Liquidity (V4 L) needed to deposit `loopAmount` token1 (LOOP) as
    ///         single-sided ABOVE the current spot. Used at init to seed each band.
    /// @dev    Caller must have currentTick <= bandTickLower (band fully above
    ///         current spot, position is LOOP-only).
    function liquidityForLoopOnly(int24 tickLower, int24 tickUpper, uint256 loopAmount)
        internal pure returns (uint128 liquidity)
    {
        uint160 sqrtA = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtB = TickMath.getSqrtPriceAtTick(tickUpper);
        liquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtA, sqrtB, loopAmount);
    }

    /// @notice Liquidity needed to deposit `ethAmount` token0 (ETH) as single-
    ///         sided BELOW the current spot. Used in repay/liquidation refills.
    /// @dev    Caller must have currentTick >= bandTickUpper (band fully below
    ///         current spot, position is ETH-only).
    function liquidityForEthOnly(int24 tickLower, int24 tickUpper, uint256 ethAmount)
        internal pure returns (uint128 liquidity)
    {
        uint160 sqrtA = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtB = TickMath.getSqrtPriceAtTick(tickUpper);
        liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtA, sqrtB, ethAmount);
    }

    /// @notice Liquidity needed to extract `ethAmount` token0 (ETH) from a
    ///         position [tickLower, tickUpper] when currentTick may be INSIDE
    ///         the range. Effective lower bound for the ETH side is
    ///         max(currentSqrt, tickLower's sqrt).
    /// @dev    Removing this L from the position returns amount0 ≈ ethAmount,
    ///         AND amount1 (LOOP) from the lower sub-range that the caller
    ///         must also drain when settling deltas.
    function liquidityForEthAtSpot(
        uint160 currentSqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 ethAmount
    ) internal pure returns (uint128 liquidity) {
        uint160 sqrtA = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtB = TickMath.getSqrtPriceAtTick(tickUpper);
        uint160 effLow = currentSqrtPriceX96 > sqrtA ? currentSqrtPriceX96 : sqrtA;
        if (effLow >= sqrtB) return 0; // sub-range empty (band fully below spot)
        liquidity = LiquidityAmounts.getLiquidityForAmount0(effLow, sqrtB, ethAmount);
    }

    /// @notice Pool ETH (in wei) corresponding to a V4 sqrtPriceX96.
    /// @dev    Inverts sqrtPriceX96AtEth:
    ///             V + eth = sqrt(K · 1e18) · 2^96 / sqrtPriceX96
    function ethAtSqrtPrice(uint160 sqrtPriceX96) internal pure returns (uint256 eth) {
        uint256 sqrtKscaled = sqrt(K * 1e18);
        uint256 vPlusEth = FullMath.mulDiv(sqrtKscaled, 1 << 96, sqrtPriceX96);
        eth = vPlusEth > VIRTUAL_ETH ? vPlusEth - VIRTUAL_ETH : 0;
    }

    /// @notice ETH value (wei) of `loopAmount` LOOP at the given V4 sqrtPriceX96.
    /// @dev    spot ETH/LOOP = 1 / V4_price = 2^192 / sqrtPriceX96². Computed
    ///         in two FullMath steps to avoid overflow.
    function loopValueInEth(uint160 sqrtPriceX96, uint256 loopAmount) internal pure returns (uint256 ethWei) {
        uint256 step1 = FullMath.mulDiv(loopAmount, 1 << 96, uint256(sqrtPriceX96));
        ethWei = FullMath.mulDiv(step1, 1 << 96, uint256(sqrtPriceX96));
    }

    /// @notice Liquidation pool ETH (wei) for a position opened at `borrowEth`.
    /// @dev    Position is liquidatable when collateral_value < debt × 1.5,
    ///         which corresponds to spot ETH/LOOP at 60% of borrow time.
    ///         Solving (V + eth_liq)² = 0.6 × (V + eth_borrow)² yields:
    ///             eth_liq = sqrt(0.6) × (V + eth_borrow) − V
    function liquidationEthForBorrowEth(uint256 borrowEth) internal pure returns (uint256 liqEth) {
        // sqrt(0.6) ≈ 0.774596669241483377 — scaled by 1e18
        uint256 SQRT_06_X18 = 774_596_669_241_483_377;
        uint256 vPlus = (VIRTUAL_ETH + borrowEth) * SQRT_06_X18 / 1e18;
        liqEth = vPlus > VIRTUAL_ETH ? vPlus - VIRTUAL_ETH : 0;
    }

    /// @notice Inverse of liquidityForEthOnly — how much ETH a given V4 liquidity
    ///         delta yields when removed from a band currently below the spot.
    /// @dev    amount0 = L · (√B − √A) · 2^96 / (√A · √B) — single-sided amount0
    ///         formula (currentTick < tickLower).
    function ethForLiquidityRemoved(int24 tickLower, int24 tickUpper, uint128 liquidity)
        internal pure returns (uint256 ethAmount)
    {
        uint160 sqrtA = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtB = TickMath.getSqrtPriceAtTick(tickUpper);
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        // amount0 formula
        uint256 numerator1 = uint256(liquidity) << 96;
        uint256 numerator2 = sqrtB - sqrtA;
        ethAmount = FullMath.mulDiv(numerator1, numerator2, sqrtB) / sqrtA;
    }

    // ─── Internals ──────────────────────────────────────────────────────────

    /// @dev  Babylonian sqrt — for our use ranges (~2e25), 50 iterations enough.
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

    /// @notice Public form of _alignUp — aligns `t` upward to the nearest
    ///         multiple of TICK_SPACING. Used by the hook for sub-range refill.
    function alignUpToSpacing(int24 t) internal pure returns (int24) {
        return _alignUp(t, TICK_SPACING);
    }
}
