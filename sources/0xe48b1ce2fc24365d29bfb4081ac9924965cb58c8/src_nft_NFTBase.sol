// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "solady/tokens/ERC721.sol";
import {LibString} from "solady/utils/LibString.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

interface ISpinRouter {
    function buy(PoolKey calldata key, uint256 minOut, bytes calldata hookData) external payable;
}

abstract contract NFTBase is ERC721 {
    uint256 public constant MAX_SUPPLY = 3**9;
    uint256 public constant MINT_REQUIREMENT = 13_000 ether;
    uint256 public constant LOCK_DURATION = 7 days;
    uint96 public constant MAX_ROYALTY_BPS = 10000;

    // Singularity
    uint256 public constant SINGULARITY_MAX = 5000;
    uint256 public constant SINGULARITY_SPIN_COST = 13_000 ether;
    uint256 public constant SINGULARITY_MAX_PER_ADDRESS = 3;
    uint256 public constant SINGULARITY_VORTEX_COST = 2;
    uint256 public constant SINGULARITY_ETH_THRESHOLD = 15 ether;
    uint256 public constant SINGULARITY_ID_OFFSET = 30000;

    enum Rarity { Common, Rare, Epic, Legendary, Mythic }

    IERC20Minimal public immutable token;
    address public immutable hook;
    uint96 public immutable royaltyBps;
    address public immutable royaltyReceiver;
    address public immutable DEPLOYER;

    ISpinRouter public spinRouter;
    PoolKey public poolKey;

    uint256 public nextTokenId;
    uint256 public nextSingularityId;
    bool public mintingEnabled;
    uint256 public publicMintTime;
    string public baseURI;
    string public contractURIString;

    struct MintRecord {
        address minter;
        uint256 amount;
        uint256 unlockTime;
    }

    mapping(uint256 => MintRecord) public mintRecords;
    mapping(address => uint256) public preRegisterTime;
    mapping(uint256 => uint256) public stakedAmount;
    mapping(uint256 => bool) public isStaked;
    mapping(address => bool) public hasMinted;
    mapping(address => uint256) public mintedTokenId;

    // Singularity mappings
    mapping(uint256 => Rarity) public singularityRarity;
    mapping(address => uint256) public singularityMintedCount;
    uint256 public totalSingularityMinted;

    error MintingNotEnabled();
    error InsufficientBalance();
    error MaxSupplyReached();
    error TransferFailed();
    error NotHook();
    error LockNotExpired();
    error AlreadyMinted();
    error MintingNotYetOpen();
    error AlreadyPreRegistered();
    error NotNftOwner();
    error AlreadyInitialized();
    error StakedNFTCannotTransfer();
    error ZeroHookAddress();
    error RoyaltyTooHigh();
    error SwapAlreadyConfigured();
    error SingularityNotActive();
    error InsufficientVortex();
    error SingularityMaxReached();
    error VortexStaked();
    error SingularityPerAddressLimit();

    modifier onlyHook() {
        if (msg.sender != hook) revert NotHook();
        _;
    }

    constructor(address token_, address hook_, string memory baseURI_, string memory contractURI_, address royaltyReceiver_, uint96 royaltyBps_, address deployer_) {
        if (hook_ == address(0)) revert ZeroHookAddress();
        if (royaltyBps_ > MAX_ROYALTY_BPS) revert RoyaltyTooHigh();
        DEPLOYER = deployer_;
        token = IERC20Minimal(token_);
        hook = hook_;
        baseURI = baseURI_;
        contractURIString = contractURI_;
        royaltyBps = royaltyBps_;
        royaltyReceiver = royaltyReceiver_;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);
        if (from != address(0) && to != address(0)) {
            if (isStaked[tokenId]) revert StakedNFTCannotTransfer();
        }
    }

    function setSwapConfig(address router_, PoolKey calldata key_) external {
        if (msg.sender != DEPLOYER) revert NotHook();
        if (address(spinRouter) != address(0)) revert SwapAlreadyConfigured();
        spinRouter = ISpinRouter(router_);
        poolKey = key_;
    }

    function name() public pure override returns (string memory) {
        return "Vortex of SPIN";
    }

    function symbol() public pure override returns (string memory) {
        return "VORTEX";
    }

    function contractURI() public view returns (string memory) {
        return contractURIString;
    }

    function royaltyInfo(uint256, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount) {
        receiver = royaltyReceiver;
        royaltyAmount = (salePrice * royaltyBps) / 10000;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == 0x01ffc9a7 ||
            interfaceId == 0x80ac58cd ||
            interfaceId == 0x2a55205a ||
            interfaceId == type(ERC721).interfaceId;
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        return LibString.toString(value);
    }

    function _toHexString(address addr) internal pure returns (string memory) {
        return LibString.toHexString(addr);
    }
}
