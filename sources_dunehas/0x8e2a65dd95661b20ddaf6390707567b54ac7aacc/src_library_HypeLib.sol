// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {HypeCurve} from "./HypeCurve.sol";
import {HypeCore} from "./HypeCore.sol";
import {HypeTypes} from "../HypeTypes.sol";

interface IERC20Seed {
    function transfer(address, uint256) external returns (bool);
}

/// @title  HypeLib — external, hook-facing: seeding, TWAP ring, liquidation scan.
/// @notice Delegate-called by the hook (keeps the hook under EIP-170). Uses
///         HypeCore internals (inlined here). Liquidation SEIZES the whole
///         position into the reserve (no fire-sale) — the cascade fix.
library HypeLib {
    using StateLibrary for IPoolManager;
    using HypeCore for HypeTypes.HypeState;

    error TokenTransferFailed();

    event PositionLiquidated(uint256 indexed id, address indexed owner, HypeTypes.Side side);

    // ─── band seeding (TOKEN-only LP at the band's range) ───────────────────
    function seedSingleBand(HypeTypes.HypeState storage s, IPoolManager pm, address token, uint256 bandId)
        external returns (int24 tickLower, int24 tickUpper, uint128 liquidity)
    {
        require(s.bands[bandId].liquidity == 0, "seeded");
        (tickLower, tickUpper) = HypeCurve.bandToV4Ticks(bandId);
        uint256 alloc = HypeCurve.loopAllocForBand(bandId);
        liquidity = HypeCurve.liquidityForLoopOnly(tickLower, tickUpper, alloc);

        (BalanceDelta delta,) = pm.modifyLiquidity(
            s.poolKey,
            ModifyLiquidityParams({ tickLower: tickLower, tickUpper: tickUpper,
                liquidityDelta: int128(liquidity), salt: bytes32(0) }), "");
        int128 a1 = delta.amount1();
        if (a1 < 0) {
            uint256 owed = uint256(uint128(-a1));
            pm.sync(s.poolKey.currency1);
            if (!IERC20Seed(token).transfer(address(pm), owed)) revert TokenTransferFailed();
            pm.settle();
        }
        s.bands[bandId] = HypeTypes.Band({
            v4TickLower: tickLower, v4TickUpper: tickUpper, liquidity: liquidity,
            borrowedETH: 0, realizedShortfallETH: 0, borrowedTOKEN: 0, realizedShortfallTOKEN: 0
        });
    }

    // ─── TWAP ring ──────────────────────────────────────────────────────────
    function seedTwap(HypeTypes.HypeState storage s, int24 tick, uint32 span) external {
        uint32 nowTs = uint32(block.timestamp);
        s.obs[0] = HypeTypes.Observation({
            timestamp: nowTs > span ? nowTs - span : 0, tickCumulative: 0, tick: tick, initialized: true });
        s.obs[1] = HypeTypes.Observation({
            timestamp: nowTs, tickCumulative: int56(tick) * int56(uint56(span)), tick: tick, initialized: true });
        s.obsIndex = 1;
    }

    function writeObservation(HypeTypes.HypeState storage s, IPoolManager pm, PoolId pid) external {
        uint32 nowTs = uint32(block.timestamp);
        HypeTypes.Observation memory last = s.obs[s.obsIndex];
        if (last.initialized && last.timestamp == nowTs) return;
        (, int24 curTick,,) = pm.getSlot0(pid);
        int56 newCum = last.initialized
            ? last.tickCumulative + int56(last.tick) * int56(uint56(nowTs - last.timestamp))
            : int56(0);
        uint16 nextIdx = uint16((uint256(s.obsIndex) + 1) % HypeTypes.OBS_BUFFER_SIZE);
        s.obs[nextIdx] = HypeTypes.Observation({ timestamp: nowTs, tickCumulative: newCum, tick: curTick, initialized: true });
        s.obsIndex = nextIdx;
    }

    /// @notice External TWAP view (hook delegate-calls this for getTwapTick).
    function twapTick(HypeTypes.HypeState storage s, uint32 secondsAgo) external view returns (int24, bool) {
        return HypeCore.twapTick(s, secondsAgo);
    }

    // ─── liquidation scan: TWAP-health gated, seize whole position → reserve ─
    function scanAndLiquidate(
        HypeTypes.HypeState storage s, IPoolManager pm, address token,
        uint256 liqHealthBps, uint32 twapSeconds,
        uint16 maxScan, uint16 maxLiqSwap, uint16 maxLiqBlock, uint256 numBands
    ) external {
        uint256 n = s.openIds.length;
        if (n == 0) return;
        (int24 tt, bool tok) = HypeCore.twapTick(s, twapSeconds);
        if (!tok) return;
        uint160 healthSqrtP = TickMath.getSqrtPriceAtTick(tt);

        if (uint64(block.number) != s.lastLiqBlock) { s.lastLiqBlock = uint64(block.number); s.liqsThisBlock = 0; }
        if (s.liqsThisBlock >= maxLiqBlock) return;
        uint256 blockRemaining = maxLiqBlock - s.liqsThisBlock;

        uint256 scanBudget = n < maxScan ? n : maxScan;
        uint256 maxLiq = scanBudget < maxLiqSwap ? scanBudget : maxLiqSwap;
        if (maxLiq > blockRemaining) maxLiq = blockRemaining;

        uint256[] memory toLiq = new uint256[](maxLiq);
        uint256 count;
        uint256 cursor = s.iterCursor % n;
        uint256 scanned;
        for (uint256 i = 0; i < scanBudget && count < maxLiq; i++) {
            uint256 pid = s.openIds[(cursor + i) % n];
            if (_unhealthy(s.positions[pid], healthSqrtP, liqHealthBps)) toLiq[count++] = pid;
            scanned = i + 1;
        }
        s.iterCursor = (cursor + scanned) % (n > 0 ? n : 1);
        if (count == 0) return;

        s.inLiquidation = true;
        for (uint256 i = 0; i < count; i++) _seize(s, toLiq[i], numBands);
        s.inLiquidation = false;
        s.liqsThisBlock += uint16(count);

        // Opportunistic insurance auto-heal after seizing.
        s.autoHeal(pm, token, numBands);
    }

    function _unhealthy(HypeTypes.Position storage p, uint160 sqrtP, uint256 liqBps) private view returns (bool) {
        if (p.owner == address(0)) return false;
        if (p.side == HypeTypes.Side.LONG) {
            if (p.debtETH == 0) return false;
            uint256 hv = HypeCurve.tokenValueInEth(p.holdingTOKEN, sqrtP);
            return (hv * 10_000) / p.debtETH < liqBps;
        } else {
            if (p.debtTOKEN == 0) return false;
            uint256 dv = HypeCurve.tokenValueInEth(p.debtTOKEN, sqrtP);
            if (dv == 0) return false;
            return (p.heldETH * 10_000) / dv < liqBps;
        }
    }

    /// @notice Seize the WHOLE position into the reserve. No fire-sale, no
    ///         penalty. The owed band side stays outstanding, now backed by
    ///         the seized asset in the reserve (converted later via internal
    ///         clearing / insurance auto-heal / owner rebalance).
    function _seize(HypeTypes.HypeState storage s, uint256 id, uint256 numBands) private {
        HypeTypes.Position storage p = s.positions[id];
        address pOwner = p.owner;
        HypeTypes.Side side = p.side;
        uint8 lev = p.leverage;
        uint256 col = p.collateralETH;

        if (side == HypeTypes.Side.LONG) {
            uint256 holding = p.holdingTOKEN;
            s.totalDebtETH      -= p.debtETH;
            s.totalHoldingTOKEN -= holding;
            s.reserveTOKEN      += holding;       // seized collateral → reserve
            // Bands still owed ETH; flag it (keeps band borrowable — §6.4) and
            // book provisional bad debt, healed when reserveTOKEN recycles.
            uint256 flagged = HypeCore.attributeBadDebtLong(s, p.debtETH, numBands);
            s.totalBadDebtETH += flagged;
            HypeCore.recordHistory(s, pOwner, id, lev, side, col, holding, 0, HypeTypes.HistoryKind.Liquidated);
        } else {
            uint256 held = p.heldETH;
            s.totalDebtTOKEN -= p.debtTOKEN;
            s.totalHeldETH   -= held;
            s.reserveETH     += held;             // seized collateral → reserve
            uint256 flaggedT = HypeCore.attributeBadDebtShort(s, p.debtTOKEN, numBands);
            s.totalBadDebtTOKEN += flaggedT;
            HypeCore.recordHistory(s, pOwner, id, lev, side, col, held, 0, HypeTypes.HistoryKind.Liquidated);
        }
        HypeCore.removePosition(s, id);
        emit PositionLiquidated(id, pOwner, side);
    }
}
