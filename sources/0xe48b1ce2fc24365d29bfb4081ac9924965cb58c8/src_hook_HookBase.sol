// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";

import {Token} from "../Token.sol";
import {NFT} from "../NFT.sol";

/// @title HookBase
/// @notice Base contract for SPIN V4 Hook with bonding curve, lock tax, release mechanism, and staking.
/// @dev Contains shared state, errors, events, and modifiers for all hook modules.
abstract contract HookBase is IHooks, ReentrancyGuardTransient {
    uint256 public constant TARGET_3_17 = 3**17 * 1e18;
    uint256 public constant MAX_BUY_PHASE_ONE = 1 ether;

    uint256 public constant KR = 5;
    uint256 public constant MAX_RELEASE = 1_000_000 ether;
    uint256 public constant MIN_RELEASE_INTERVAL = 10;
    uint256 public constant COOLDOWN_BLOCKS = 1;

    uint256 public constant PHASE_ONE_TAX = 2;
    uint256 public constant PHASE_TWO_TAX = 5;
    uint256 public constant TAX_DENOMINATOR = 1000;

    IPoolManager public immutable POOL_MANAGER;
    Token public immutable TOKEN;
    NFT public NFT_CONTRACT;

    Currency public immutable ETH_CURRENCY;
    Currency public immutable TOKEN_CURRENCY;

    address public immutable DEPLOYER;

    uint256 public ethCumulative;
    uint256 public lockPoolBalance;
    uint256 public lastReleaseBlock;

    uint256 public accRewardPerWeight;
    uint256 public totalWeight;
    uint256 public totalNftsStaked;
    uint256 public pendingRewards;

    // Packed: phaseTwoActivated + paused share one slot
    bool public phaseTwoActivated;
    bool public paused;

    mapping(address => uint256) public userWeight;
    mapping(address => uint256) public stakedCount;
    mapping(address => uint256) public stakedVortexCount;
    mapping(address => uint256) public singularityWeight;
    mapping(address => uint256) public rewardDebt;
    mapping(uint256 => address) public nftStaker;
    mapping(address => uint256) public lastBuyBlock;
    uint256 public lastGlobalBuyBlock;

    error NotPoolManager();
    error InvalidPool();
    error ExactOutputUnsupported();
    error BuyAmountExceedsLimit();
    error AlreadyInitialized();
    error NftAlreadyStaked();
    error NotNftOwner();
    error NotStaked();
    error InsufficientEthReserves();
    error NoSupplyToSell();
    error ZeroAmount();
    error RewardTransferFailed();
    error InvalidNFTContract();
    error SlippageLimitExceeded();
    error DuplicateNftId();
    error LiquidityAdditionsForbidden();
    error BondingCurveInconsistent();
    error NotDeployer();
    error MissingSlippageParams();
    error DirectEthTransferForbidden();
    error Paused();
    error Expired();
    error CooldownActive();

    event SpinBuy(address indexed buyer, uint256 ethIn, uint256 spinOut, uint256 taxAmount);
    event SpinSell(address indexed seller, uint256 spinIn, uint256 ethOut, uint256 taxAmount);
    event PhaseTransition(bool phaseTwo);
    event LockTaxReleased(uint256 amount, uint256 blocksElapsed);
    event Staked(address indexed user, uint256[] nftIds, uint256 newWeight);
    event Unstaked(address indexed user, uint256[] nftIds, uint256 newWeight);
    event RewardClaimed(address indexed user, uint256 amount);
    event AccRewardPerWeightUpdated(uint256 newAccRewardPerWeight);
    event EthCumulativeUpdated(uint256 newEthCumulative);
    event LastReleaseBlockUpdated(uint256 newLastReleaseBlock);
    event PausedChanged(bool paused);

    constructor(IPoolManager poolManager, Token token, NFT nft, bool skipValidation, address deployer_) {
        POOL_MANAGER = poolManager;
        TOKEN = token;
        ETH_CURRENCY = Currency.wrap(address(0));
        TOKEN_CURRENCY = Currency.wrap(address(token));
        DEPLOYER = deployer_;

        if (address(nft) != address(0)) {
            NFT_CONTRACT = nft;
        }

        if (!skipValidation) {
            Hooks.validateHookPermissions(this, getHookPermissions());
        }
    }

    function getHookPermissions() public pure virtual returns (Hooks.Permissions memory);

    modifier onlyPoolManager() {
        if (msg.sender != address(POOL_MANAGER)) revert NotPoolManager();
        _;
    }

    modifier onlyDeployer() {
        if (msg.sender != DEPLOYER) revert NotDeployer();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    function setPaused(bool _paused) external onlyDeployer {
        paused = _paused;
        emit PausedChanged(_paused);
    }

    function circulatingSupply() public view returns (uint256) {
        uint256 totalSupply = TOKEN.totalSupply();
        if (lockPoolBalance >= totalSupply) return 0;
        return totalSupply - lockPoolBalance;
    }

    function curveReserveEth() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Called by NFT contract when Singularity SPIN is contributed.
    function recordSingularitySpin(uint256 amount) external {
        if (msg.sender != address(NFT_CONTRACT)) revert InvalidNFTContract();
        lockPoolBalance += amount;
    }

    /// @notice Called by RoyaltyAutoBuy: send SPIN to the Hook to be permanently burned.
    ///         Tax from royalty buys stays in lockPoolBalance; after-tax is destroyed.
    ///         Reduces totalSupply, creating deflationary pressure on SPIN price.
    function burnContributedSPIN(uint256 amount) external {
        if (msg.sender != royaltyAutoBuy) revert InvalidNFTContract();
        bool ok = TOKEN.transferFrom(msg.sender, address(this), amount);
        if (!ok) revert RewardTransferFailed();
        TOKEN.burn(address(this), amount);
    }

    address public royaltyAutoBuy;

    function setRoyaltyAutoBuy(address addr) external onlyDeployer {
        if (royaltyAutoBuy != address(0)) revert AlreadyInitialized();
        royaltyAutoBuy = addr;
    }

    function _tryCheckPhaseTransition() internal virtual;
    function _tryRelease() internal virtual;

    receive() external payable {
        if (msg.sender != address(POOL_MANAGER)) revert DirectEthTransferForbidden();
    }
}
