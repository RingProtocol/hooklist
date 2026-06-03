// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NFTBase} from "./NFTBase.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";

interface IHookSingularity {
    function recordSingularitySpin(uint256 amount) external;
}

abstract contract NFTMinting is NFTBase, ReentrancyGuardTransient {
    uint256 public constant MAX_PAID_MINT_PER_ADDRESS = 5;
    uint256 public constant PAID_MINT_COST = 0.002 ether;

    mapping(address => uint256) public paidMintCount;

    error InsufficientPayment();
    error ExceedsPaidLimit();

    event PaidMinted(address indexed minter, uint256 quantity, uint256 totalCost);

    /// @notice Paid mint via OpenSea or direct call. Opens 1 hour before pre-registration.
    ///         Cost: 0.002 ETH each, max 5 per address. Sets hasMinted to block free mint,
    ///         but free-minted users can still paid mint.
    /// @param quantity Number of NFTs to mint (1-5)
    function paidMint(uint256 quantity) external payable nonReentrant {
        if (!mintingEnabled) revert MintingNotEnabled();
        if (block.timestamp < publicMintTime - 2 hours) revert MintingNotYetOpen();
        if (quantity == 0 || quantity > MAX_PAID_MINT_PER_ADDRESS) revert ExceedsPaidLimit();
        if (paidMintCount[msg.sender] + quantity > MAX_PAID_MINT_PER_ADDRESS) revert ExceedsPaidLimit();
        if (msg.value < PAID_MINT_COST * quantity) revert InsufficientPayment();
        if (nextTokenId + quantity > MAX_SUPPLY) revert MaxSupplyReached();

        (bool sent,) = royaltyReceiver.call{value: msg.value}("");
        if (!sent) revert TransferFailed();

        paidMintCount[msg.sender] += quantity;
        hasMinted[msg.sender] = true;

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = nextTokenId++;
            _mint(msg.sender, tokenId);
        }

        emit PaidMinted(msg.sender, quantity, msg.value);
    }

    function mint() external nonReentrant {
        _checkMintConditions(msg.sender);
        if (token.balanceOf(msg.sender) < MINT_REQUIREMENT) revert InsufficientBalance();

        uint256 tokenId = nextTokenId++;
        bool success = token.transferFrom(msg.sender, address(this), MINT_REQUIREMENT);
        if (!success) revert TransferFailed();

        _mintNft(msg.sender, tokenId);
    }

    /// @notice Mint with ETH via bonding curve. For OpenSea and direct ETH payments.
    ///         Buys SPIN with the sent ETH, then mints the NFT with the received tokens.
    /// @param minTokens Minimum SPIN to receive from the buy (slippage protection).
    function mintWithETH(uint256 minTokens) external payable nonReentrant {
        if (address(spinRouter) == address(0)) revert MintingNotEnabled();
        _checkMintConditions(msg.sender);

        uint256 balanceBefore = token.balanceOf(address(this));

        // Buy SPIN via bonding curve. Hook data encodes slippage: (minTokens, max ETH=type(uint256).max)
        spinRouter.buy{value: msg.value}(poolKey, minTokens, abi.encode(minTokens, type(uint256).max));

        uint256 received = token.balanceOf(address(this)) - balanceBefore;
        if (received < MINT_REQUIREMENT) revert InsufficientBalance();

        uint256 tokenId = nextTokenId++;
        _mintNft(msg.sender, tokenId);

        // Return leftover SPIN to user
        uint256 leftover = received - MINT_REQUIREMENT;
        if (leftover > 0) {
            bool ok = token.transfer(msg.sender, leftover);
            if (!ok) revert TransferFailed();
        }

        // Return leftover ETH to user
        uint256 ethLeft = address(this).balance;
        if (ethLeft > 0) {
            (bool sent,) = msg.sender.call{value: ethLeft}("");
            if (!sent) revert TransferFailed();
        }
    }

    function _checkMintConditions(address minter) internal view {
        if (!mintingEnabled) revert MintingNotEnabled();
        if (hasMinted[minter]) revert AlreadyMinted();
        if (nextTokenId >= MAX_SUPPLY) revert MaxSupplyReached();

        uint256 nowTime = block.timestamp;
        bool isPreRegistered = preRegisterTime[minter] > 0;

        if (isPreRegistered) {
            if (nowTime < publicMintTime - 1 hours) revert MintingNotYetOpen();
        } else {
            if (nowTime < publicMintTime) revert MintingNotYetOpen();
        }
    }

    function _mintNft(address minter, uint256 tokenId) internal {
        hasMinted[minter] = true;
        mintedTokenId[minter] = tokenId;
        stakedAmount[tokenId] = MINT_REQUIREMENT;
        mintRecords[tokenId] = MintRecord({
            minter: minter,
            amount: MINT_REQUIREMENT,
            unlockTime: block.timestamp + LOCK_DURATION
        });
        _mint(minter, tokenId);
    }

    function enableMinting(uint256 targetReachedTime) external onlyHook {
        if (mintingEnabled) revert AlreadyInitialized();
        // Always target tomorrow UTC 14:00 regardless of when Phase 2 triggers.
        // 23:00 today → 14:00 tomorrow (pre-reg at 13:00)
        // 10:00 today → 14:00 tomorrow (pre-reg at 13:00)
        publicMintTime = (targetReachedTime / 1 days) * 1 days + 1 days + 14 hours;
        mintingEnabled = true;
    }

    function preRegister() external {
        if (!mintingEnabled) revert MintingNotEnabled();
        if (preRegisterTime[msg.sender] != 0) revert AlreadyPreRegistered();
        preRegisterTime[msg.sender] = block.timestamp;
    }

    function hasPriorityAccess(address user) external view returns (bool) {
        uint256 regTime = preRegisterTime[user];
        // forge-lint: disable-next-line(block-timestamp)
        return regTime > 0 && block.timestamp >= publicMintTime - 1 hours && block.timestamp < publicMintTime;
    }

    function setStakedStatus(uint256 tokenId, bool isStaked_) external onlyHook {
        isStaked[tokenId] = isStaked_;
    }

    function mintSingularity(uint256[] calldata vortexIds) external nonReentrant {
        if (!mintingEnabled) revert MintingNotEnabled();
        if (address(hook).balance < SINGULARITY_ETH_THRESHOLD) revert SingularityNotActive();
        if (vortexIds.length != SINGULARITY_VORTEX_COST) revert InsufficientVortex();
        if (nextSingularityId >= SINGULARITY_MAX) revert SingularityMaxReached();
        if (singularityMintedCount[msg.sender] >= SINGULARITY_MAX_PER_ADDRESS) revert SingularityPerAddressLimit();
        if (token.balanceOf(msg.sender) < SINGULARITY_SPIN_COST) revert InsufficientBalance();

        // Burn Vortex NFTs
        for (uint256 i = 0; i < SINGULARITY_VORTEX_COST; i++) {
            uint256 vid = vortexIds[i];
            if (ownerOf(vid) != msg.sender) revert NotNftOwner();
            if (isStaked[vid]) revert VortexStaked();
            _burn(vid);
        }

        // Transfer SPIN to Hook contract — enters lockPoolBalance
        bool ok = token.transferFrom(msg.sender, hook, SINGULARITY_SPIN_COST);
        if (!ok) revert TransferFailed();
        IHookSingularity(hook).recordSingularitySpin(SINGULARITY_SPIN_COST);

        // Random rarity via keccak256 with prevrandao, sender, and count
        uint256 seed = uint256(keccak256(abi.encodePacked(
            block.prevrandao, msg.sender, totalSingularityMinted
        )));
        uint256 roll = seed % 10000; // 0-9999
        Rarity rarity;
        if (roll < 5000) rarity = Rarity.Common;           // 50%
        else if (roll < 7500) rarity = Rarity.Rare;        // 25%
        else if (roll < 9000) rarity = Rarity.Epic;        // 15%
        else if (roll < 9800) rarity = Rarity.Legendary;   // 8%
        else rarity = Rarity.Mythic;                        // 2%

        uint256 tokenId = SINGULARITY_ID_OFFSET + nextSingularityId;
        nextSingularityId++;
        totalSingularityMinted++;
        singularityRarity[tokenId] = rarity;
        singularityMintedCount[msg.sender]++;

        stakedAmount[tokenId] = SINGULARITY_SPIN_COST;
        _mint(msg.sender, tokenId);
    }

    function getSingularityWeight(uint256 tokenId) external view returns (uint256) {
        if (tokenId < SINGULARITY_ID_OFFSET) return 0;
        return _singularityWeight(singularityRarity[tokenId]);
    }

    function _singularityWeight(Rarity rarity) internal pure returns (uint256) {
        if (rarity == Rarity.Common) return 200;
        if (rarity == Rarity.Rare) return 300;
        if (rarity == Rarity.Epic) return 500;
        if (rarity == Rarity.Legendary) return 1000;
        return 2500; // Mythic
    }

    function unlockTokens() external {
        uint256 tokenId = mintedTokenId[msg.sender];
        MintRecord storage record = mintRecords[tokenId];
        if (record.minter != msg.sender) revert NotNftOwner();
        if (block.timestamp < record.unlockTime) revert LockNotExpired();

        uint256 amount = stakedAmount[tokenId];
        if (amount == 0) return;

        stakedAmount[tokenId] = 0;
        record.unlockTime = 0;

        bool success = token.transfer(msg.sender, amount);
        if (!success) revert TransferFailed();
    }
}
