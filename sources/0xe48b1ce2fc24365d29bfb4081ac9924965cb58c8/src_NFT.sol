// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NFTBase} from "./nft/NFTBase.sol";
import {NFTMinting} from "./nft/NFTMinting.sol";
import {NFTMetadata} from "./nft/NFTMetadata.sol";

/// @title NFT
/// @notice SPIN NFT with minting threshold, pre-registration, and 7-day staking lock.
contract NFT is NFTMinting, NFTMetadata {
    constructor(address token_, address hook_, string memory baseURI_, string memory contractURI_, address royaltyReceiver_, uint96 royaltyBps_, address deployer_)
        NFTBase(token_, hook_, baseURI_, contractURI_, royaltyReceiver_, royaltyBps_, deployer_)
    {}
}
