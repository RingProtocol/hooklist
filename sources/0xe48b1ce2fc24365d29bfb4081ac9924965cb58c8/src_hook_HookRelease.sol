// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {HookBase} from "./HookBase.sol";

/// @title HookRelease
/// @notice Handles phase transition and lock pool tax release mechanisms.
/// @dev Manages the two-phase system and distributes locked tax as staking rewards.
abstract contract HookRelease is HookBase {
    function _tryCheckPhaseTransition() internal override {
        if (!phaseTwoActivated && circulatingSupply() >= TARGET_3_17) {
            phaseTwoActivated = true;
            paused = false; // auto-unpause at phase transition
            if (address(NFT_CONTRACT) != address(0) && !NFT_CONTRACT.mintingEnabled()) {
                NFT_CONTRACT.enableMinting(block.timestamp);
            }
            emit PhaseTransition(true);
            emit PausedChanged(false);
        }
    }

    function _tryRelease() internal override {
        if (block.number == lastReleaseBlock) return;
        if (!phaseTwoActivated) return;
        uint256 blocksElapsed = block.number - lastReleaseBlock;
        if (blocksElapsed < MIN_RELEASE_INTERVAL) return;

        _tryCheckPhaseTransition();

        uint256 supply = circulatingSupply();
        if (supply >= TARGET_3_17 || lockPoolBalance == 0) return;

        uint256 deficit = TARGET_3_17 - supply;
        uint256 releaseAmount = (deficit * KR * blocksElapsed) / 100000;

        if (releaseAmount > lockPoolBalance) {
            releaseAmount = lockPoolBalance;
        }
        if (releaseAmount > MAX_RELEASE) {
            releaseAmount = MAX_RELEASE;
        }
        if (releaseAmount == 0) return;

        lockPoolBalance -= releaseAmount;
        lastReleaseBlock = block.number;
        _notifyReward(releaseAmount);

        emit LastReleaseBlockUpdated(lastReleaseBlock);
        emit LockTaxReleased(releaseAmount, blocksElapsed);
    }

    function _notifyReward(uint256 amount) internal {
        if (totalWeight > 0) {
            uint256 totalReward = amount + pendingRewards;
            accRewardPerWeight += (totalReward * 1e36) / totalWeight;
            pendingRewards = 0;
            emit AccRewardPerWeightUpdated(accRewardPerWeight);
        } else {
            pendingRewards += amount;
        }
    }
}
