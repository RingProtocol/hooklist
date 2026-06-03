// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/*//////////////////////////////////////////////////////////////
                       Hype Staking
        Stake HYPE → earn ETH from leverage fees / insurance
//////////////////////////////////////////////////////////////*/

import {ERC20} from "solady/src/tokens/ERC20.sol";

interface IHypeStaking {
    function notifyReward() external payable;
}

/// @notice MasterChef-style ETH-reward staking. The hook routes the stakers'
///         slice of borrow/close fees here (adaptive split — see PERP_DESIGN
///         §7); stakers claim a pro-rata share of the accumulated ETH. Instant
///         unstake (no cooldown).
///
///         Edge case: rewards arriving while `totalStaked == 0` are held in
///         `pendingUntilStakers` and credited to the first staker. The deployer
///         seeds a small baseline stake at launch to avoid an early-staker
///         windfall.
contract HypeStaking is IHypeStaking {
    ERC20   public immutable token;
    address public immutable hook;
    address public immutable owner;

    uint256 public totalStaked;
    /// @dev Accumulated ETH reward per staked HYPE, scaled by 1e18.
    uint256 public accRewardPerShareE18;
    uint256 public pendingUntilStakers;

    struct Stake {
        uint256 amount;
        uint256 rewardDebt; // amount * accRewardPerShareE18 / 1e18 at last interaction
    }
    mapping(address => Stake) public stakes;
    mapping(address => uint256) internal _claimable;

    error NotHook();
    error ZeroAmount();
    error InsufficientStake();
    error TransferFailed();
    error NothingToClaim();
    error Reentrancy();
    error ZeroAddress();

    event Staked(address indexed user, uint256 amount, uint256 newTotal);
    event Unstaked(address indexed user, uint256 amount, uint256 newTotal);
    event Claimed(address indexed user, uint256 amount);
    event RewardNotified(uint256 amount, uint256 newAccPerShareE18);
    event PendingFlushed(uint256 amount);

    uint256 private _locked = 1;
    modifier nonReentrant() {
        if (_locked != 1) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }

    constructor(ERC20 token_, address hook_, address owner_) {
        if (address(token_) == address(0) || hook_ == address(0) || owner_ == address(0)) {
            revert ZeroAddress();
        }
        token = token_;
        hook  = hook_;
        owner = owner_;
    }

    /// @notice Direct ETH deposits — only hook (fee notify) and owner (manual
    ///         top-up). Gated so a griefer can't inflate accRewardPerShareE18
    ///         with dust to skew APR or force tiny accumulator updates.
    receive() external payable {
        if (msg.sender != hook && msg.sender != owner) revert NotHook();
        if (msg.value > 0) _addReward(msg.value);
    }

    /// @notice Hook calls this with the stakers' fee slice.
    function notifyReward() external payable {
        if (msg.sender != hook) revert NotHook();
        if (msg.value == 0) return;
        _addReward(msg.value);
    }

    function _addReward(uint256 amount) internal {
        if (totalStaked > 0) {
            accRewardPerShareE18 += (amount * 1e18) / totalStaked;
        } else {
            pendingUntilStakers += amount;
        }
        emit RewardNotified(amount, accRewardPerShareE18);
    }

    function _harvest(address user) internal {
        Stake storage s = stakes[user];
        if (s.amount > 0) {
            uint256 owed = (s.amount * accRewardPerShareE18) / 1e18;
            if (owed > s.rewardDebt) _claimable[user] += (owed - s.rewardDebt);
        }
    }

    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _harvest(msg.sender);

        if (!token.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

        // First staker post-empty gets the entire pendingUntilStakers bucket.
        if (totalStaked == 0 && pendingUntilStakers > 0) {
            uint256 flushed = pendingUntilStakers;
            pendingUntilStakers = 0;
            _claimable[msg.sender] += flushed;
            emit PendingFlushed(flushed);
        }

        Stake storage s = stakes[msg.sender];
        s.amount    += amount;
        totalStaked += amount;
        s.rewardDebt = (s.amount * accRewardPerShareE18) / 1e18;
        emit Staked(msg.sender, amount, totalStaked);
    }

    function unstake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        Stake storage s = stakes[msg.sender];
        if (amount > s.amount) revert InsufficientStake();

        _harvest(msg.sender);
        s.amount    -= amount;
        totalStaked -= amount;
        s.rewardDebt = (s.amount * accRewardPerShareE18) / 1e18;

        if (!token.transfer(msg.sender, amount)) revert TransferFailed();
        emit Unstaked(msg.sender, amount, totalStaked);
    }

    function claim() external nonReentrant returns (uint256 amount) {
        _harvest(msg.sender);
        uint256 want = _claimable[msg.sender];
        if (want == 0) revert NothingToClaim();

        // Accumulator truncation can drift the sum of pending balances a few
        // wei above the actual ETH balance over many events. Clamp so the last
        // claimer never reverts; residual stays for a later retry.
        uint256 bal = address(this).balance;
        amount = want <= bal ? want : bal;
        _claimable[msg.sender] = want - amount;

        Stake storage s = stakes[msg.sender];
        s.rewardDebt = (s.amount * accRewardPerShareE18) / 1e18;

        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) {
            _claimable[msg.sender] = want; // restore full
            revert TransferFailed();
        }
        emit Claimed(msg.sender, amount);
    }

    // ─── Views ──────────────────────────────────────────────────────────────

    function pendingRewards(address user) external view returns (uint256) {
        Stake memory s = stakes[user];
        uint256 owed = (s.amount * accRewardPerShareE18) / 1e18;
        uint256 unclaimed = owed > s.rewardDebt ? owed - s.rewardDebt : 0;
        return unclaimed + _claimable[user];
    }

    function claimable(address user) external view returns (uint256) {
        return _claimable[user];
    }

    function stakedBalance(address user) external view returns (uint256) {
        return stakes[user].amount;
    }
}
