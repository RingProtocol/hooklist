// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {HookBase} from "./HookBase.sol";

/// @title HookStaking
/// @notice NFT staking mechanism with reward distribution based on staked NFT weight.
///         Supports both Vortex (count-based weight) and Singularity (rarity-based weight).
/// @dev Inherits ReentrancyGuardTransient from HookBase.
abstract contract HookStaking is HookBase {
    uint256 internal constant SINGULARITY_ID_OFFSET = 30000;

    function _calcWeight(uint256 n) internal pure returns (uint256) {
        if (n <= 3) return n * 100;
        if (n <= 10) return 300 + (n - 3) * 50;
        return 650 + (n - 10) * 10;
    }

    function _isSingularity(uint256 tokenId) internal pure returns (bool) {
        return tokenId >= SINGULARITY_ID_OFFSET;
    }

    function stake(uint256[] calldata nftIds) external nonReentrant whenNotPaused {
        if (address(NFT_CONTRACT) == address(0)) revert InvalidNFTContract();
        _claimPendingReward(msg.sender);

        uint256 vortexAdded;
        uint256 singWeightAdded;
        uint256 count = nftIds.length;

        for (uint256 i = 0; i < count; i++) {
            uint256 nftId = nftIds[i];
            for (uint256 j = 0; j < i; j++) {
                if (nftIds[j] == nftId) revert DuplicateNftId();
            }
            if (nftStaker[nftId] != address(0)) revert NftAlreadyStaked();
            if (NFT_CONTRACT.ownerOf(nftId) != msg.sender) revert NotNftOwner();
            nftStaker[nftId] = msg.sender;
            NFT_CONTRACT.setStakedStatus(nftId, true);

            if (_isSingularity(nftId)) {
                singWeightAdded += NFT_CONTRACT.getSingularityWeight(nftId);
            } else {
                vortexAdded++;
            }
        }

        uint256 oldWeight = userWeight[msg.sender];
        uint256 newVortexCount = stakedVortexCount[msg.sender] + vortexAdded;
        uint256 newSingWeight = singularityWeight[msg.sender] + singWeightAdded;
        uint256 newWeight = _calcWeight(newVortexCount) + newSingWeight;

        totalWeight = totalWeight - oldWeight + newWeight;
        userWeight[msg.sender] = newWeight;
        stakedCount[msg.sender] = stakedCount[msg.sender] + count;
        stakedVortexCount[msg.sender] = newVortexCount;
        singularityWeight[msg.sender] = newSingWeight;
        totalNftsStaked += count;
        rewardDebt[msg.sender] = (newWeight * accRewardPerWeight) / 1e36;

        emit Staked(msg.sender, nftIds, newWeight);
    }

    function unstake(uint256[] calldata nftIds) external nonReentrant whenNotPaused {
        if (address(NFT_CONTRACT) == address(0)) revert InvalidNFTContract();
        _claimPendingReward(msg.sender);

        uint256 vortexRemoved;
        uint256 singWeightRemoved;
        uint256 count = nftIds.length;

        for (uint256 i = 0; i < count; i++) {
            uint256 nftId = nftIds[i];
            for (uint256 j = 0; j < i; j++) {
                if (nftIds[j] == nftId) revert DuplicateNftId();
            }
            if (nftStaker[nftId] != msg.sender) revert NotStaked();
            delete nftStaker[nftId];
            NFT_CONTRACT.setStakedStatus(nftId, false);

            if (_isSingularity(nftId)) {
                singWeightRemoved += NFT_CONTRACT.getSingularityWeight(nftId);
            } else {
                vortexRemoved++;
            }
        }

        uint256 oldWeight = userWeight[msg.sender];
        uint256 newVortexCount = stakedVortexCount[msg.sender] - vortexRemoved;
        uint256 newSingWeight = singularityWeight[msg.sender] - singWeightRemoved;
        uint256 newWeight = _calcWeight(newVortexCount) + newSingWeight;

        totalWeight = totalWeight - oldWeight + newWeight;
        userWeight[msg.sender] = newWeight;
        stakedCount[msg.sender] = stakedCount[msg.sender] - count;
        stakedVortexCount[msg.sender] = newVortexCount;
        singularityWeight[msg.sender] = newSingWeight;
        totalNftsStaked -= count;
        rewardDebt[msg.sender] = (newWeight * accRewardPerWeight) / 1e36;

        emit Unstaked(msg.sender, nftIds, newWeight);
    }

    function emergencyUnstake(uint256[] calldata nftIds) external nonReentrant {
        if (address(NFT_CONTRACT) == address(0)) revert InvalidNFTContract();

        uint256 vortexRemoved;
        uint256 singWeightRemoved;
        uint256 count = nftIds.length;

        for (uint256 i = 0; i < count; i++) {
            uint256 nftId = nftIds[i];
            for (uint256 j = 0; j < i; j++) {
                if (nftIds[j] == nftId) revert DuplicateNftId();
            }
            if (nftStaker[nftId] != msg.sender) revert NotStaked();
            delete nftStaker[nftId];
            NFT_CONTRACT.setStakedStatus(nftId, false);

            if (_isSingularity(nftId)) {
                singWeightRemoved += NFT_CONTRACT.getSingularityWeight(nftId);
            } else {
                vortexRemoved++;
            }
        }

        uint256 oldWeight = userWeight[msg.sender];
        uint256 newVortexCount = stakedVortexCount[msg.sender] - vortexRemoved;
        uint256 newSingWeight = singularityWeight[msg.sender] - singWeightRemoved;
        uint256 newWeight = _calcWeight(newVortexCount) + newSingWeight;

        totalWeight = totalWeight - oldWeight + newWeight;
        userWeight[msg.sender] = newWeight;
        stakedCount[msg.sender] = stakedCount[msg.sender] - count;
        stakedVortexCount[msg.sender] = newVortexCount;
        singularityWeight[msg.sender] = newSingWeight;
        totalNftsStaked -= count;
        rewardDebt[msg.sender] = (newWeight * accRewardPerWeight) / 1e36;

        emit Unstaked(msg.sender, nftIds, newWeight);
    }

    function claim() external nonReentrant whenNotPaused {
        _claimPendingReward(msg.sender);
    }

    function _claimPendingReward(address user) internal {
        uint256 pending = _pendingReward(user);
        if (pending > 0) {
            rewardDebt[user] = (userWeight[user] * accRewardPerWeight) / 1e36;
            if (!TOKEN.transfer(user, pending)) revert RewardTransferFailed();
            emit RewardClaimed(user, pending);
        }
    }

    function _pendingReward(address user) internal view returns (uint256) {
        uint256 userReward = (userWeight[user] * accRewardPerWeight) / 1e36;
        if (userReward <= rewardDebt[user]) return 0;
        return userReward - rewardDebt[user];
    }
}
