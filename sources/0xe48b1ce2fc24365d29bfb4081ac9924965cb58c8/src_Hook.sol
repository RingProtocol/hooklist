// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Token} from "./Token.sol";
import {NFT} from "./NFT.sol";
import {HookBase} from "./hook/HookBase.sol";
import {HookSwap} from "./hook/HookSwap.sol";
import {HookRelease} from "./hook/HookRelease.sol";
import {HookStaking} from "./hook/HookStaking.sol";

/// @title Hook
/// @notice SPIN V4 Hook with bonding curve, lock tax, release mechanism, and staking.
/// @dev Combines HookSwap, HookRelease, and HookStaking modules.
///      Inherits from HookRelease, HookSwap, HookStaking (diamond inheritance via HookBase).
contract Hook is HookRelease, HookSwap, HookStaking {
    constructor(IPoolManager poolManager, Token token, NFT nft, bool skipValidation, address deployer_)
        HookBase(poolManager, token, nft, skipValidation, deployer_)
    {
        token.setHook(address(this));
    }

    function setNFTContract(NFT nft_) external onlyDeployer {
        if (address(NFT_CONTRACT) != address(0)) revert AlreadyInitialized();
        if (address(nft_) == address(0)) revert InvalidNFTContract();
        NFT_CONTRACT = nft_;
    }
}
