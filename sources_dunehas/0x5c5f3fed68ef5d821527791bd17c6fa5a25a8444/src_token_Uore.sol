// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../upegs/Upeg.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {IStartableToken} from "./IStartableToken.sol";

contract Uore is Upeg, ERC20, Ownable, IStartableToken {
    error AddressCanNotReceiveUpeg();

    uint256 public constant UNIT_PER_UPEG = 1e18;
    uint256 public constant INITIAL_SUPPLY = 10_000e18;
    uint256 public constant WAD = 1e18;
    uint256 public constant DAY = 1 days;
    uint256 public constant DAY_1_EMISSION = 1_000e18;
    uint256 public constant DAILY_DECAY_WAD = 0.99e18;

    uint256 constant MAX_BUY_PRECISION = 100000;
    uint256 constant _startMaxBuyCount =
        (INITIAL_SUPPLY * 250) / MAX_BUY_PRECISION;
    uint256 constant _addMaxBuyPercentPerSec = 3;

    enum Class {
        None,
        Mortal,
        Hero,
        Demigod,
        Titan,
        God
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

    address internal _notMintableAccount;
    uint256 _startTime;
    address public hook;
    address public pool;

    mapping(address => uint256) public userTotalPower;
    mapping(address => uint256) public userRewardDebt;
    mapping(address => uint256) public userTaxScalarSnapshot;
    mapping(address => uint256) public userPending;

    mapping(uint256 => address) public stakedBy;

    uint256 public accUorePerPower;
    uint256 public taxScalar;
    uint256 public motherlodePool;
    uint256 public totalStakedPower;

    uint256 public sumPendingScaled;
    uint256 public sumWeightedDebt;

    uint256 public cumulativeMinted;
    uint256 public cumulativeBurned;

    uint64 public launchTimestamp;
    uint64 public lastUpdateTimestamp;
    uint64 public lastMotherlodeRollBlock;

    uint256 internal nextUnanchoredId;
    mapping(uint256 => uint64) public mintBlockOf;

    uint16 public constant ROLL_QUEUE_SIZE = 64;
    uint64 public constant ROLL_COOLDOWN_BLOCKS = 5;
    uint256 public constant ROLL_DENOM = 90_000;
    uint256 public constant ROLL_HIT_INTERCEPT = 60;
    uint256 public constant ROLL_HIT_SLOPE = 840;
    uint256 public constant ROLL_HIT_CAP = 900;
    uint256 public constant MIN_BUY_ETH = 0.1 ether;

    uint256 public constant MOTHERLODE_PCT = 20;

    PendingRoll[64] public pendingRolls;
    uint16 public rollHead;
    uint16 public rollTail;
    uint16 public rollCount;
    mapping(address => uint64) public lastRollBlockBy;

    mapping(address => uint64) internal _txRollBlock;
    mapping(address => uint16) internal _txRollIdxPlusOne;

    function _setTxRollIdx(address user, uint16 idxPlusOne) internal {
        _txRollBlock[user] = uint64(block.number);
        _txRollIdxPlusOne[user] = idxPlusOne;
    }

    function _getTxRollIdx(address user) internal view returns (uint16) {
        if (_txRollBlock[user] != block.number) return 0;
        return _txRollIdxPlusOne[user];
    }

    mapping(address => uint256) public stakerPos;
    mapping(uint256 => address) public posToStaker;
    mapping(uint256 => uint256) internal bit;
    uint256 public stakerCount;

    mapping(address => uint256[]) internal _userStakedUpegs;
    mapping(uint256 => uint256) internal _stakedListIdx;

    mapping(address => uint256) public totalClaimedBy;
    mapping(address => uint16) public motherlodeWinsCountBy;
    mapping(address => uint256) public motherlodeWinTotalBy;

    MotherlodeHitRecord[] internal _motherlodeHits;
    BuybackRecord[] internal _buybacks;

    event Staked(address indexed user, uint256 indexed upegId, uint16 power);
    event Unstaked(address indexed user, uint256 indexed upegId, uint16 power);
    event Claimed(address indexed user, uint256 payout, uint256 tax);
    event MotherlodeRollRecorded(
        address indexed buyer,
        uint64 indexed buyBlock,
        uint128 poolSnapshot,
        uint128 ethPaid
    );
    event MotherlodeHit(
        address indexed buyer,
        address indexed staker,
        uint256 buyerPayout,
        uint256 stakerPayout
    );
    event UpegAnchored(uint256 indexed upegId, uint256 seed);
    event BuybackSucceeded(uint256 ethSpent, uint256 uoreBurned);
    event BuybackFailed(uint256 ethAmount);

    constructor(address owner_) {
        _initializeOwner(owner_);
        _mint(owner_, INITIAL_SUPPLY);
        cumulativeMinted = INITIAL_SUPPLY;
        _notMintableAccount = owner_;
        taxScalar = WAD;
        nextUnanchoredId = 0;
    }

    modifier canReceiveUpegs(address addr) {
        if (!_canReceiveUpegs(addr)) revert AddressCanNotReceiveUpeg();
        _;
    }

    modifier onlyHook() {
        require(msg.sender == hook, "only hook");
        _;
    }

    function name() public pure override returns (string memory) {
        return "Uore";
    }

    function symbol() public pure override returns (string memory) {
        return "UORE";
    }

    function start(address newPool) external onlyHook {
        require(pool == address(0), "started");
        require(newPool != address(0), "zero pool");
        pool = newPool;
        _startTime = block.timestamp;
        launchTimestamp = uint64(block.timestamp);
        lastUpdateTimestamp = uint64(block.timestamp);
    }

    function isStarted() public view returns (bool) {
        return pool != address(0);
    }

    function maxBuy() public view returns (uint256) {
        if (!isStarted()) return 0;
        uint256 count = _startMaxBuyCount +
            (INITIAL_SUPPLY *
                (block.timestamp - _startTime) *
                _addMaxBuyPercentPerSec) /
            MAX_BUY_PRECISION;
        if (count > INITIAL_SUPPLY) count = INITIAL_SUPPLY;
        return count;
    }

    function setHook(address newHook) external onlyOwner {
        require(hook == address(0), "hook already set");
        require(newHook != address(0), "zero hook");
        hook = newHook;
    }

    function setImageParamsProvider(
        address imageParamsProvider
    ) public onlyOwner {
        _setImageParamsProvider(imageParamsProvider);
    }

    function setRandomSeedProvider(
        address provider
    ) public onlyOwner {
        _setRandomSeedProvider(provider);
    }

    function multiplierOf(Class c) public pure returns (uint8) {
        if (c == Class.Mortal) return 1;
        if (c == Class.Hero) return 2;
        if (c == Class.Demigod) return 3;
        if (c == Class.Titan) return 4;
        if (c == Class.God) return 5;
        return 0;
    }

    function getClass(uint256 upegId) public view returns (Class) {
        uint256 seed = _upegs[upegId];
        if (seed == 0 || seed == 1) return Class.None;
        uint256 r = uint256(
            keccak256(abi.encode(upegId, seed, "UORE_CLASS"))
        ) % 10000;
        if (r < 6000) return Class.Mortal;
        if (r < 8500) return Class.Hero;
        if (r < 9500) return Class.Demigod;
        if (r < 9900) return Class.Titan;
        return Class.God;
    }

    function getHash(uint256 upegId) public view returns (uint8) {
        uint256 seed = _upegs[upegId];
        if (seed == 0 || seed == 1) return 0;
        return
            uint8(
                (uint256(keccak256(abi.encode(upegId, seed, "UORE_HASH"))) %
                    100) + 1
            );
    }

    function getMiningPower(uint256 upegId) public view returns (uint16) {
        return uint16(getHash(upegId)) * uint16(multiplierOf(getClass(upegId)));
    }

    function stakeForMining(uint256 upegId) external {
        _service(3, 2);
        _stakeForMining(msg.sender, upegId);
    }

    function stakeForMiningBatch(uint256[] calldata upegIds) external {
        _service(3, 2);
        for (uint256 i; i < upegIds.length; ++i) {
            _stakeForMining(msg.sender, upegIds[i]);
        }
    }

    function unstakeFromMining(uint256 upegId) external {
        _service(3, 2);
        _unstakeFromMining(msg.sender, upegId);
    }

    function unstakeFromMiningBatch(uint256[] calldata upegIds) external {
        _service(3, 2);
        for (uint256 i; i < upegIds.length; ++i) {
            _unstakeFromMining(msg.sender, upegIds[i]);
        }
    }

    function claim() external {
        _service(3, 2);
        _claim(msg.sender, true);
    }

    function anchorPending(uint8 maxToAnchor) external {
        require(maxToAnchor <= 20, "too many");
        _service(maxToAnchor, 2);
    }

    function resolveMotherlode(uint8 maxToResolve) external {
        require(maxToResolve <= 64, "too many");
        _service(2, maxToResolve);
    }

    function recordPendingRoll(address buyer, uint128 ethPaid) external onlyHook {
        _service(2, 2);
        if (rollCount >= ROLL_QUEUE_SIZE) return;
        uint64 lastBy = lastRollBlockBy[buyer];
        if (lastBy != 0 && block.number - lastBy < ROLL_COOLDOWN_BLOCKS) return;
        if (ethPaid < MIN_BUY_ETH) return;

        uint16 idx = rollTail;
        pendingRolls[idx] = PendingRoll({
            buyBlock: uint64(block.number),
            buyer: buyer,
            poolSnapshot: uint128(motherlodePool),
            ethPaid: ethPaid
        });
        rollTail = (rollTail + 1) % ROLL_QUEUE_SIZE;
        unchecked { ++rollCount; }
        lastMotherlodeRollBlock = uint64(block.number);
        lastRollBlockBy[buyer] = uint64(block.number);

        _setTxRollIdx(buyer, idx + 1);

        emit MotherlodeRollRecorded(
            buyer,
            uint64(block.number),
            uint128(motherlodePool),
            ethPaid
        );
    }

    function burnFromHook(uint256 amount) external onlyHook {
        _service(2, 2);
        _burn(msg.sender, amount);
        cumulativeBurned += amount;
        _buybacks.push(
            BuybackRecord({
                blockNumber: uint64(block.number),
                ethSpent: 0,
                uoreBurned: uint128(amount)
            })
        );
    }

    function pendingRewards(address user) public view returns (uint256) {
        uint256 effectiveAccUorePerPower = accUorePerPower;
        if (
            launchTimestamp != 0 &&
            block.timestamp > lastUpdateTimestamp &&
            totalStakedPower > 0
        ) {
            uint256 emission = _emissionBetween(
                lastUpdateTimestamp - launchTimestamp,
                block.timestamp - launchTimestamp
            );
            uint256 stakerEmission = emission - ((emission * MOTHERLODE_PCT) / 100);
            effectiveAccUorePerPower +=
                (stakerEmission * WAD) /
                totalStakedPower;
        }

        uint256 snap = userTaxScalarSnapshot[user];
        if (snap == 0) {
            uint256 baseAccr = userTotalPower[user] *
                (effectiveAccUorePerPower - userRewardDebt[user]);
            return baseAccr / WAD;
        }

        uint256 effPending = (userPending[user] * taxScalar) / snap;
        uint256 effDebt = (userRewardDebt[user] * taxScalar) / snap;

        uint256 newBase;
        if (effectiveAccUorePerPower > effDebt) {
            newBase = (userTotalPower[user] *
                (effectiveAccUorePerPower - effDebt)) / WAD;
        }

        return effPending + newBase;
    }

    function queueDepth() public view returns (uint16) {
        return rollCount;
    }

    function motherlodeOdds() external pure returns (uint8, uint16) {
        return (1, 100);
    }

    function oddsForEth(uint128 ethPaid) external pure returns (uint256 threshold, uint256 denom) {
        if (ethPaid < MIN_BUY_ETH) return (0, ROLL_DENOM);
        threshold = ROLL_HIT_INTERCEPT + (uint256(ethPaid) * ROLL_HIT_SLOPE) / 1 ether;
        if (threshold > ROLL_HIT_CAP) threshold = ROLL_HIT_CAP;
        denom = ROLL_DENOM;
    }

    function upegSeedOf(uint256 upegId) external view returns (uint256) {
        return _upegs[upegId];
    }

    function stakedUpegsCount(address user) external view returns (uint256) {
        return _userStakedUpegs[user].length;
    }

    function stakedUpegAt(address user, uint256 index) external view returns (uint256) {
        return _userStakedUpegs[user][index];
    }

    function getBuybacksTotal() external view returns (uint256) {
        return _buybacks.length;
    }

    function buybackAt(uint256 index) external view returns (BuybackRecord memory) {
        return _buybacks[index];
    }

    function getMotherlodeHitsTotal() external view returns (uint256) {
        return _motherlodeHits.length;
    }

    function motherlodeHitAt(
        uint256 index
    ) external view returns (MotherlodeHitRecord memory) {
        return _motherlodeHits[index];
    }

    function currentEmissionPerSec() public view returns (uint256) {
        if (launchTimestamp == 0) return 0;
        uint256 elapsed = block.timestamp - launchTimestamp;
        uint256 daysElapsed = elapsed / DAY;
        return (DAY_1_EMISSION * _powWad(DAILY_DECAY_WAD, daysElapsed)) / WAD / DAY;
    }

    function _service(uint8 maxAnchors, uint8 maxRolls) internal {
        _settleGlobal();
        _anchorSweep(maxAnchors);
        _resolveMotherlode(maxRolls);
    }

    function _stakeForMining(address user, uint256 upegId) internal {
        require(_owns[user][upegId], "not owner");
        _settleUser(user);
        uint16 power = getMiningPower(upegId);
        require(power > 0, "not anchored");

        stakedBy[upegId] = user;
        userTotalPower[user] += power;
        totalStakedPower += power;
        sumWeightedDebt += (uint256(power) * accUorePerPower * WAD) / taxScalar;

        _addStakerPower(user, power);
        _userStakedUpegs[user].push(upegId);
        _stakedListIdx[upegId] = _userStakedUpegs[user].length;

        _transferUpeg(user, address(this), upegId);
        _afterUpegTransferred(user, address(this), upegId);
        emit Staked(user, upegId, power);
    }

    function _unstakeFromMining(address user, uint256 upegId) internal {
        require(stakedBy[upegId] == user, "not staker");
        _claim(user, false);

        uint16 power = getMiningPower(upegId);
        userTotalPower[user] -= power;
        totalStakedPower -= power;
        uint256 debtRemoval = (uint256(power) * accUorePerPower * WAD) / taxScalar;
        if (debtRemoval > sumWeightedDebt) debtRemoval = sumWeightedDebt;
        sumWeightedDebt -= debtRemoval;

        _subStakerPower(user, power);
        delete stakedBy[upegId];
        _removeFromStakedList(user, upegId);

        _transferUpeg(address(this), user, upegId);
        _afterUpegTransferred(address(this), user, upegId);
        emit Unstaked(user, upegId, power);
    }

    function _claim(address user, bool requirePending) internal {
        _settleUser(user);
        uint256 pending = userPending[user];
        if (requirePending) require(pending > 0, "nothing pending");
        if (pending == 0) return;

        uint256 tax = pending / 10;
        uint256 payout = pending - tax;

        uint256 pendingContrib = (pending * WAD) / taxScalar;
        if (pendingContrib > sumPendingScaled) pendingContrib = sumPendingScaled;
        sumPendingScaled -= pendingContrib;
        userPending[user] = 0;

        if (tax > 0) _distributeToRefined(tax);
        if (payout > 0) {
            _mint(user, payout);
            cumulativeMinted += payout;
            totalClaimedBy[user] += payout;
        }
        emit Claimed(user, payout, tax);
    }

    function _settleGlobal() internal {
        if (launchTimestamp == 0) return;
        uint64 last = lastUpdateTimestamp;
        if (last == 0 || block.timestamp <= last) return;
        uint256 emission = _emissionBetween(
            last - launchTimestamp,
            block.timestamp - launchTimestamp
        );
        if (emission == 0) {
            lastUpdateTimestamp = uint64(block.timestamp);
            return;
        }
        uint256 motherlodeAdd = (emission * MOTHERLODE_PCT) / 100;
        uint256 stakerEmission = emission - motherlodeAdd;
        motherlodePool += motherlodeAdd;
        if (totalStakedPower > 0) {
            accUorePerPower += (stakerEmission * WAD) / totalStakedPower;
        } else {
            motherlodePool += stakerEmission;
        }
        lastUpdateTimestamp = uint64(block.timestamp);
    }

    function _settleUser(address user) internal {
        uint256 snap = userTaxScalarSnapshot[user];
        uint256 power = userTotalPower[user];

        if (snap == 0) {
            userTaxScalarSnapshot[user] = taxScalar;
            userRewardDebt[user] = accUorePerPower;
            if (power > 0) {
                sumWeightedDebt += (power * accUorePerPower * WAD) / taxScalar;
            }
            return;
        }

        uint256 oldPendingContrib = (userPending[user] * WAD) / snap;
        uint256 oldDebtContrib = (power * userRewardDebt[user] * WAD) / snap;
        if (oldPendingContrib > sumPendingScaled) oldPendingContrib = sumPendingScaled;
        if (oldDebtContrib > sumWeightedDebt) oldDebtContrib = sumWeightedDebt;
        sumPendingScaled -= oldPendingContrib;
        sumWeightedDebt -= oldDebtContrib;

        uint256 newPending = userPending[user];
        if (snap != taxScalar) {
            newPending = (newPending * taxScalar) / snap;
        }

        uint256 effDebt = (userRewardDebt[user] * taxScalar) / snap;
        if (accUorePerPower > effDebt && power > 0) {
            uint256 newRewards = (power * (accUorePerPower - effDebt)) / WAD;
            newPending += newRewards;
        }

        userPending[user] = newPending;
        userRewardDebt[user] = accUorePerPower;
        userTaxScalarSnapshot[user] = taxScalar;

        sumPendingScaled += (newPending * WAD) / taxScalar;
        if (power > 0) {
            sumWeightedDebt += (power * accUorePerPower * WAD) / taxScalar;
        }
    }

    function _distributeToRefined(uint256 tax) internal {
        if (tax == 0) return;
        uint256 totalEff = _totalEffectivePending();
        if (totalEff == 0 || totalStakedPower == 0) {
            motherlodePool += tax;
            return;
        }
        uint256 ratio = ((totalEff + tax) * WAD) / totalEff;
        if (ratio == WAD) {
            motherlodePool += tax;
            return;
        }
        accUorePerPower = (accUorePerPower * ratio) / WAD;
        taxScalar = (taxScalar * ratio) / WAD;
    }

    function totalEffectivePending() external view returns (uint256) {
        return _totalEffectivePending();
    }

    function _totalEffectivePending() internal view returns (uint256) {
        uint256 effSettled = (sumPendingScaled * taxScalar) / WAD;
        uint256 emissionTotal = (totalStakedPower * accUorePerPower) / WAD;
        uint256 debtTotal = (taxScalar * sumWeightedDebt) / WAD / WAD;
        if (debtTotal > emissionTotal) return effSettled;
        return effSettled + (emissionTotal - debtTotal);
    }

    function _anchorSweep(uint8 maxToAnchor) internal {
        uint256 i = nextUnanchoredId;
        uint256 total = _upegsTotalCount;
        if (i == total) return;
        uint256 end = i + maxToAnchor;
        if (end > total) end = total;
        while (i < end) {
            if (gasleft() < 150_000) break;
            uint256 upegId = i + 1;
            uint64 mb = mintBlockOf[upegId];
            if (mb == 0 || mb + 1 >= block.number) break;

            if (_upegs[upegId] != 1) {
                unchecked {
                    ++i;
                }
                continue;
            }

            bytes32 entropy;
            if (block.number - mb > 256) {
                entropy = keccak256(abi.encode(upegId, mb, "UORE_FALLBACK"));
            } else {
                entropy = keccak256(abi.encode(upegId, blockhash(mb + 1)));
            }
            Random memory random = Random({seed: uint256(entropy), nonce: 0});
            uint256 packed = _nextUpeg(random);
            _upegs[upegId] = packed;
            emit UpegAnchored(upegId, packed);
            unchecked {
                ++i;
            }
        }
        if (i != nextUnanchoredId) nextUnanchoredId = i;
    }

    function _resolveMotherlode(uint8 maxToResolve) internal {
        uint16 i = rollHead;
        uint8 processed;
        while (processed < maxToResolve && rollCount > 0) {
            if (gasleft() < 100_000) break;
            PendingRoll memory p = pendingRolls[i];
            if (p.buyBlock >= block.number) break;
            bytes32 h = blockhash(p.buyBlock + 1);
            if (h == bytes32(0) && block.number - p.buyBlock > 256) {
                h = keccak256(
                    abi.encode(
                        p.buyer,
                        p.buyBlock,
                        p.poolSnapshot,
                        "MOTHERLODE_FALLBACK"
                    )
                );
                _resolveOne(p, h, true);
                delete pendingRolls[i];
                i = (i + 1) % ROLL_QUEUE_SIZE;
                unchecked { --rollCount; }
                ++processed;
                continue;
            }
            if (h == bytes32(0)) break;
            _resolveOne(p, h, false);
            delete pendingRolls[i];
            i = (i + 1) % ROLL_QUEUE_SIZE;
            unchecked { --rollCount; }
            ++processed;
        }
        rollHead = i;
    }

    function _resolveOne(PendingRoll memory p, bytes32 h, bool isFallback) internal {
        if (p.buyer == address(0) || p.ethPaid == 0) return;

        uint256 rng = uint256(keccak256(abi.encode(h, p.buyer, p.poolSnapshot)));

        uint256 threshold = ROLL_HIT_INTERCEPT +
            (uint256(p.ethPaid) * ROLL_HIT_SLOPE) / 1 ether;
        if (threshold > ROLL_HIT_CAP) threshold = ROLL_HIT_CAP;
        if (rng % ROLL_DENOM >= threshold) return;

        uint256 actualPot = p.poolSnapshot;
        if (actualPot > motherlodePool) actualPot = motherlodePool;
        if (actualPot == 0) return;

        uint256 half = actualPot / 2;
        motherlodePool -= actualPot;

        _mint(p.buyer, half);
        cumulativeMinted += half;
        motherlodeWinsCountBy[p.buyer]++;
        motherlodeWinTotalBy[p.buyer] += half;

        address winner;
        if (totalStakedPower > 0 && !isFallback) {
            uint256 stakerRng = uint256(keccak256(abi.encode(rng, "STAKER")));
            winner = _stakerByCumulativePower(stakerRng % totalStakedPower);
            _settleUser(winner);
            userPending[winner] += half;
            sumPendingScaled += (half * WAD) / taxScalar;
        } else {
            motherlodePool += half;
        }

        _motherlodeHits.push(
            MotherlodeHitRecord({
                blockNumber: uint64(block.number),
                buyer: p.buyer,
                staker: winner,
                buyerPayout: uint128(half),
                stakerPayout: uint128(winner == address(0) ? 0 : half)
            })
        );
        emit MotherlodeHit(p.buyer, winner, half, winner == address(0) ? 0 : half);
    }

    function _onTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        if (pool == address(0)) return;

        if (from == pool && to != address(0)) {
            if (_notMintableAccount == to) return;
            if (to == hook) return;
            require(isStarted(), "not started");
            require(amount <= maxBuy(), "buy limit");
            _mintDeferredUpegs(to, amount / UNIT_PER_UPEG);
            return;
        }

        if (to == pool && from != address(0)) {
            uint16 idxPlusOne = _getTxRollIdx(from);
            if (idxPlusOne > 0) {
                uint16 idx = idxPlusOne - 1;
                if (pendingRolls[idx].buyer != address(0) && rollCount > 0) {
                    unchecked { --rollCount; }
                }
                delete pendingRolls[idx];
                _setTxRollIdx(from, 0);
            }
        }

        uint256 fromMaxAllowed = balanceOf(from) / UNIT_PER_UPEG;
        uint256 fromCount = _counts[from];
        uint256 fromRemoveCount = fromCount > fromMaxAllowed
            ? fromCount - fromMaxAllowed
            : 0;

        uint256 toMaxAllowed = balanceOf(to) / UNIT_PER_UPEG;
        uint256 toCount = _counts[to];
        uint256 toReceiveAllowed = toCount < toMaxAllowed
            ? toMaxAllowed - toCount
            : 0;

        if (fromRemoveCount == 0) return;

        if (!_canReceiveUpegs(to)) {
            toReceiveAllowed = 0;
        }

        uint256 moveQty = fromRemoveCount < toReceiveAllowed
            ? fromRemoveCount
            : toReceiveAllowed;
        if (moveQty > 0) _moveUpegs(from, to, moveQty);

        _burnUpegs(from, fromRemoveCount - moveQty);
    }

    function _mintDeferredUpegs(address user, uint256 qty) internal {
        for (uint256 i; i < qty; ++i) {
            uint256 upegId = ++_upegsTotalCount;
            _upegs[upegId] = 1;
            mintBlockOf[upegId] = uint64(block.number);
            _insertExistingUpegToOwner(user, upegId);
            emit OnUpegMinted(user, upegId);
        }
    }

    function _burnUpegs(address user, uint256 qty) internal {
        for (uint256 i; i < qty; ++i) {
            uint256 count = _counts[user];
            if (count == 0) break;
            uint256 upegId = _ownedUpegs[user][count - 1];
            require(stakedBy[upegId] == address(0), "staked");
            _burnUpeg(user, upegId);
        }
    }

    function _moveUpegs(
        address from,
        address to,
        uint256 qty
    ) internal canReceiveUpegs(to) {
        for (uint256 i; i < qty; ++i) {
            uint256 count = _counts[from];
            if (count == 0) break;
            uint256 upegId = _ownedUpegs[from][count - 1];
            require(stakedBy[upegId] == address(0), "staked");
            _transferUpeg(from, to, upegId);
        }
    }

    function _canReceiveUpegs(address addr) internal view returns (bool) {
        return
            addr != pool &&
            addr != address(0) &&
            addr != address(this) &&
            addr != hook;
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._afterTokenTransfer(from, to, amount);
        if (pool == address(0)) return;
        _service(1, 2);
        _onTokenTransfer(from, to, amount);
    }

    function _afterUpegTransferred(
        address from,
        address to,
        uint256
    ) internal override {
        _transfer(from, to, UNIT_PER_UPEG);
    }

    function transferUpeg(address to, uint256 upegId)
        external
        virtual
        override(Upeg)
        onlyUpegOwner(upegId)
        canReceiveUpegs(to)
    {
        _transferUpeg(msg.sender, to, upegId);
        _afterUpegTransferred(msg.sender, to, upegId);
    }

    function transferUpegsList(address to, uint256[] calldata upegIds)
        external
        virtual
        override(Upeg)
        canReceiveUpegs(to)
    {
        uint256 len = upegIds.length;
        if (len == 0) return;
        for (uint256 i = 0; i < len; ++i) {
            if (!_owns[msg.sender][upegIds[i]]) revert NotUpegOwner();
            _transferUpeg(msg.sender, to, upegIds[i]);
        }
        _afterUpegsListTransferred(msg.sender, to, upegIds);
    }

    function _afterUpegsListTransferred(
        address from,
        address to,
        uint256[] calldata upegIds
    ) internal override {
        _transfer(from, to, UNIT_PER_UPEG * upegIds.length);
    }

    function _removeFromStakedList(address user, uint256 upegId) internal {
        uint256 idxPlusOne = _stakedListIdx[upegId];
        if (idxPlusOne == 0) return;
        uint256 idx = idxPlusOne - 1;
        uint256 lastIdx = _userStakedUpegs[user].length - 1;
        if (idx != lastIdx) {
            uint256 lastId = _userStakedUpegs[user][lastIdx];
            _userStakedUpegs[user][idx] = lastId;
            _stakedListIdx[lastId] = idx + 1;
        }
        _userStakedUpegs[user].pop();
        delete _stakedListIdx[upegId];
    }

    function _addStakerPower(address user, uint256 power) internal {
        uint256 pos = stakerPos[user];
        if (pos == 0) {
            pos = ++stakerCount;
            stakerPos[user] = pos;
            posToStaker[pos] = user;
            uint256 lsb = pos & (~pos + 1);
            uint256 lo = pos - lsb + 1;
            for (uint256 i = lo; i < pos; ++i) {
                bit[pos] += userTotalPower[posToStaker[i]];
            }
        }
        _fenwickAdd(pos, power);
    }

    function _subStakerPower(address user, uint256 power) internal {
        uint256 pos = stakerPos[user];
        require(pos != 0, "not staker");
        _fenwickSub(pos, power);
    }

    function _fenwickAdd(uint256 index, uint256 amount) internal {
        while (index <= stakerCount) {
            bit[index] += amount;
            index += index & (~index + 1);
        }
    }

    function _fenwickSub(uint256 index, uint256 amount) internal {
        while (index <= stakerCount) {
            bit[index] -= amount;
            index += index & (~index + 1);
        }
    }

    function _stakerByCumulativePower(
        uint256 target
    ) internal view returns (address) {
        uint256 idx;
        uint256 bitMask = 1;
        while (bitMask < stakerCount) bitMask <<= 1;
        uint256 sum;
        while (bitMask != 0) {
            uint256 next = idx + bitMask;
            if (next <= stakerCount && sum + bit[next] <= target) {
                idx = next;
                sum += bit[next];
            }
            bitMask >>= 1;
        }
        return posToStaker[idx + 1];
    }

    function _emissionBetween(
        uint256 elapsedStart,
        uint256 elapsedEnd
    ) internal pure returns (uint256) {
        if (elapsedEnd <= elapsedStart) return 0;
        return _cumulativeEmission(elapsedEnd) - _cumulativeEmission(elapsedStart);
    }

    function _cumulativeEmission(
        uint256 elapsed
    ) internal pure returns (uint256) {
        uint256 daysElapsed = elapsed / DAY;
        uint256 rem = elapsed % DAY;
        uint256 decayPow = _powWad(DAILY_DECAY_WAD, daysElapsed);
        uint256 fullDays = (DAY_1_EMISSION * (WAD - decayPow)) /
            (WAD - DAILY_DECAY_WAD);
        uint256 dayRate = (DAY_1_EMISSION * decayPow) / WAD;
        return fullDays + (dayRate * rem) / DAY;
    }

    function _powWad(
        uint256 x,
        uint256 n
    ) internal pure returns (uint256 result) {
        result = WAD;
        while (n > 0) {
            if ((n & 1) == 1) result = (result * x) / WAD;
            x = (x * x) / WAD;
            n >>= 1;
        }
    }
}
