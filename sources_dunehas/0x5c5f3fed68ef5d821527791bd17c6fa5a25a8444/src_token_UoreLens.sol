// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Uore.sol";
import "../svg_generation/UpegMetadata.sol";

interface IUoreHookBucket {
    function ethBucket() external view returns (uint128);
}

contract UoreLens {
    uint256 private constant DAY = 1 days;

    Uore public immutable token;
    address public immutable hook;

    struct GlobalStats {
        uint256 totalSupply;
        uint256 cumulativeMinted;
        uint256 cumulativeBurned;
        uint256 currentEmissionPerSec;
        uint256 motherlodePool;
        uint256 totalStakedPower;
        uint256 totalEffectivePending;
        uint256 stakerCount;
        uint64 launchTimestamp;
        uint64 lastUpdateTimestamp;
        uint128 ethBucket;
        uint16 motherlodeQueueLen;
        uint64 daysSinceLaunch;
        uint256 motherlodeFloorThreshold;
        uint256 motherlodeCapThreshold;
        uint256 motherlodeOddsDenom;
    }

    struct UserStats {
        uint256 uoreBalance;
        uint16 upegsHeld;
        uint16 upegsStaked;
        uint32 totalStakedPower;
        uint256 pendingRewards;
        uint256 totalClaimed;
        uint16 motherlodeWinsCount;
        uint256 motherlodeWinTotal;
        uint256 refinedBoostBps;
    }

    struct UpegInfo {
        uint256 id;
        uint256 seed;
        uint8 classIdx;
        uint8 hash;
        uint16 miningPower;
        bool staked;
        bool anchored;
        bool pendingReady;
        bool expired;
        uint64 mintBlock;
        address staker;
    }

    /// @notice Full trait breakdown for a Upeg, with user-facing field names.
    /// Indices reference per-trait sprite variants (0 = none/absent).
    struct UpegTraits {
        // Derived
        uint8 classIdx;        // 1-5: Mortal/Hero/Demigod/Titan/God
        uint8 hashValue;       // 1-100
        uint16 miningPower;    // hashValue × class multiplier
        // Visual (variant indices)
        uint8 background;
        uint8 skin;
        uint8 face;
        uint8 eyes;
        uint8 crown;
        uint8 ear;
        uint8 cloth;
        uint8 mouth;
        uint8 tool;
        // Color picks (palette indices)
        uint8 skinColor;
        uint8 eyesColor;
        uint8 crownColor;
        uint8 earColor;
        uint8 mouthColor;
        uint8 toolColor;
    }

    struct StakerInfo {
        address user;
        uint32 power;
        uint256 pendingRewards;
        uint16 upegsStaked;
    }

    struct PendingRoll {
        uint64 buyBlock;
        address buyer;
        uint128 poolSnapshot;
        uint128 ethPaid;
    }

    struct MotherlodeHitRecord {
        uint64 blockNumber;
        address buyer;
        address staker;
        uint128 buyerPayout;
        uint128 stakerPayout;
    }

    struct BuybackRecord {
        uint64 blockNumber;
        uint128 ethSpent;
        uint128 uoreBurned;
    }

    constructor(address token_, address hook_) {
        token = Uore(token_);
        hook = hook_;
    }

    function getGlobalStats() external view returns (GlobalStats memory) {
        uint64 launchTimestamp = token.launchTimestamp();
        uint64 daysSinceLaunch = launchTimestamp == 0
            ? 0
            : uint64((block.timestamp - launchTimestamp) / DAY);
        (uint256 floorThr, uint256 denom) = token.oddsForEth(uint128(token.MIN_BUY_ETH()));
        (uint256 capThr, ) = token.oddsForEth(uint128(1 ether));
        return
            GlobalStats({
                totalSupply: token.totalSupply(),
                cumulativeMinted: token.cumulativeMinted(),
                cumulativeBurned: token.cumulativeBurned(),
                currentEmissionPerSec: token.currentEmissionPerSec(),
                motherlodePool: token.motherlodePool(),
                totalStakedPower: token.totalStakedPower(),
                totalEffectivePending: token.totalEffectivePending(),
                stakerCount: token.stakerCount(),
                launchTimestamp: launchTimestamp,
                lastUpdateTimestamp: token.lastUpdateTimestamp(),
                ethBucket: _ethBucket(),
                motherlodeQueueLen: token.queueDepth(),
                daysSinceLaunch: daysSinceLaunch,
                motherlodeFloorThreshold: floorThr,
                motherlodeCapThreshold: capThr,
                motherlodeOddsDenom: denom
            });
    }

    function getUserStats(address user) external view returns (UserStats memory) {
        // Refined-ore boost: ratio of current taxScalar to user's snapshot (in basis points)
        uint256 snap = token.userTaxScalarSnapshot(user);
        uint256 scalar = token.taxScalar();
        uint256 boost = snap == 0 ? 10_000 : (scalar * 10_000) / snap;
        return
            UserStats({
                uoreBalance: token.balanceOf(user),
                upegsHeld: uint16(token.OwnerUpegsCount(user)),
                upegsStaked: uint16(token.stakedUpegsCount(user)),
                totalStakedPower: uint32(token.userTotalPower(user)),
                pendingRewards: token.pendingRewards(user),
                totalClaimed: token.totalClaimedBy(user),
                motherlodeWinsCount: token.motherlodeWinsCountBy(user),
                motherlodeWinTotal: token.motherlodeWinTotalBy(user),
                refinedBoostBps: boost
            });
    }

    function getOwnedUpegs(
        address user,
        uint256 page,
        uint256 pageSize
    ) external view returns (UpegInfo[] memory infos) {
        UpegSeedData[] memory pageData = token.OwnerUpegsPage(user, page, pageSize);
        infos = new UpegInfo[](pageData.length);
        for (uint256 i; i < pageData.length; ++i) {
            infos[i] = _upegInfo(pageData[i].id, pageData[i].seed);
        }
    }

    function getStakedUpegs(
        address user,
        uint256 page,
        uint256 pageSize
    ) external view returns (UpegInfo[] memory infos) {
        uint256 count = token.stakedUpegsCount(user);
        uint256 startIndex = page * pageSize;
        if (pageSize == 0 || startIndex >= count) return new UpegInfo[](0);
        uint256 end = startIndex + pageSize;
        if (end > count) end = count;
        infos = new UpegInfo[](end - startIndex);
        for (uint256 i; i < infos.length; ++i) {
            uint256 upegId = token.stakedUpegAt(user, startIndex + i);
            infos[i] = getUpegInfo(upegId);
        }
    }

    function getUpegInfo(
        uint256 upegId
    ) public view returns (UpegInfo memory) {
        return _upegInfo(upegId, token.upegSeedOf(upegId));
    }

    /// @notice Returns the full trait breakdown for a Upeg with user-facing field names.
    /// Frontends/marketplaces can decode trait labels directly without an off-chain mapping.
    function getUpegTraits(uint256 upegId) external view returns (UpegTraits memory traits) {
        uint256 seed = token.upegSeedOf(upegId);
        UpegMetadata memory m = UpegMetadataLibrary.decode(seed);
        uint8 classIdx = uint8(token.getClass(upegId));
        uint8 hashVal = token.getHash(upegId);
        traits = UpegTraits({
            classIdx: classIdx,
            hashValue: hashVal,
            miningPower: token.getMiningPower(upegId),
            background: m.background,
            skin: m.skin,
            face: m.face,
            eyes: m.eyes,
            crown: m.crown,
            ear: m.ear,
            cloth: m.cloth,
            mouth: m.mouth,
            tool: m.tool,
            skinColor: m.skinColor,
            eyesColor: m.eyesColor,
            crownColor: m.crownColor,
            earColor: m.earColor,
            mouthColor: m.mouthColor,
            toolColor: m.toolColor
        });
    }

    function getStakerPage(
        uint256 page,
        uint256 pageSize
    ) external view returns (StakerInfo[] memory infos) {
        uint256 startIndex = page * pageSize + 1;
        uint256 stakerCount = token.stakerCount();
        if (pageSize == 0 || startIndex > stakerCount) {
            return new StakerInfo[](0);
        }
        uint256 end = startIndex + pageSize;
        if (end > stakerCount + 1) end = stakerCount + 1;
        infos = new StakerInfo[](end - startIndex);
        for (uint256 i; i < infos.length; ++i) {
            address user = token.posToStaker(startIndex + i);
            infos[i] = StakerInfo({
                user: user,
                power: uint32(token.userTotalPower(user)),
                pendingRewards: token.pendingRewards(user),
                upegsStaked: uint16(token.stakedUpegsCount(user))
            });
        }
    }

    function getStakerCount() external view returns (uint256) {
        return token.stakerCount();
    }

    function getRecentMotherlodeHits(
        uint256 limit
    ) external view returns (MotherlodeHitRecord[] memory records) {
        uint256 total = token.getMotherlodeHitsTotal();
        if (limit > total) limit = total;
        records = new MotherlodeHitRecord[](limit);
        for (uint256 i; i < limit; ++i) {
            Uore.MotherlodeHitRecord memory record = token.motherlodeHitAt(
                total - 1 - i
            );
            records[i] = MotherlodeHitRecord({
                blockNumber: record.blockNumber,
                buyer: record.buyer,
                staker: record.staker,
                buyerPayout: record.buyerPayout,
                stakerPayout: record.stakerPayout
            });
        }
    }

    function getMotherlodeHitsTotal() external view returns (uint256) {
        return token.getMotherlodeHitsTotal();
    }

    function getRecentBuybacks(
        uint256 limit
    ) external view returns (BuybackRecord[] memory records) {
        uint256 total = token.getBuybacksTotal();
        if (limit > total) limit = total;
        records = new BuybackRecord[](limit);
        for (uint256 i; i < limit; ++i) {
            Uore.BuybackRecord memory record = token.buybackAt(total - 1 - i);
            records[i] = BuybackRecord({
                blockNumber: record.blockNumber,
                ethSpent: record.ethSpent,
                uoreBurned: record.uoreBurned
            });
        }
    }

    function getBuybacksTotal() external view returns (uint256) {
        return token.getBuybacksTotal();
    }

    function getPendingRolls()
        external
        view
        returns (PendingRoll[] memory rolls)
    {
        uint16 depth = token.queueDepth();
        rolls = new PendingRoll[](depth);
        uint16 idx = token.rollHead();
        uint16 size = token.ROLL_QUEUE_SIZE();
        for (uint16 i; i < depth; ++i) {
            (
                uint64 buyBlock,
                address buyer,
                uint128 poolSnapshot,
                uint128 ethPaid
            ) = token.pendingRolls(idx);
            rolls[i] = PendingRoll({
                buyBlock: buyBlock,
                buyer: buyer,
                poolSnapshot: poolSnapshot,
                ethPaid: ethPaid
            });
            idx = (idx + 1) % size;
        }
    }

    function _upegInfo(
        uint256 upegId,
        uint256 seed
    ) internal view returns (UpegInfo memory) {
        uint64 mintBlock = token.mintBlockOf(upegId);
        bool anchored = seed > 1;
        address staker = token.stakedBy(upegId);
        return
            UpegInfo({
                id: upegId,
                seed: seed,
                classIdx: uint8(token.getClass(upegId)),
                hash: token.getHash(upegId),
                miningPower: token.getMiningPower(upegId),
                staked: staker != address(0),
                anchored: anchored,
                pendingReady: !anchored &&
                    mintBlock != 0 &&
                    mintBlock + 1 < block.number,
                expired: !anchored &&
                    mintBlock != 0 &&
                    block.number - mintBlock > 256,
                mintBlock: mintBlock,
                staker: staker
            });
    }

    function _ethBucket() internal view returns (uint128) {
        if (hook == address(0)) return 0;
        try IUoreHookBucket(hook).ethBucket() returns (uint128 bucket) {
            return bucket;
        } catch {
            return 0;
        }
    }
}
