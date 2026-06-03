// SPDX-License-Identifier: MIT
//
//   ████████╗██╗ ██████╗██╗  ██╗██████╗
//   ╚══██╔══╝██║██╔════╝██║ ██╔╝██╔══██╗
//      ██║   ██║██║     █████╔╝ ██████╔╝
//      ██║   ██║██║     ██╔═██╗ ██╔══██╗
//      ██║   ██║╚██████╗██║  ██╗██║  ██║
//      ╚═╝   ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝
//
//   Website: https://tickr.xyz
//   Twitter: https://x.com/tickrxyz
//
pragma solidity >=0.8.9;

import "./token_v4.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IAllowanceTransfer} from "@uniswap/v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";

interface IStateView {
    function getSlot0(PoolId poolId) external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint24 protocolFee,
        uint24 lpFee
    );
}

interface ITokenRegistry {
    function registerSymbol(string calldata symbol) external;
}

interface ITickrOwnerNFT {
    function mintFor(address to, address tickerToken) external returns (uint256 tokenId);
}

contract Factory is ReentrancyGuard {
    // ─────────────────────────────────────────────────────────────────────
    // External addresses — Uniswap v4 deployment (chain-specific, set at deploy)
    //
    // PERMIT2 is canonical (same address on every chain). The other four are
    // immutable so each chain gets its own factory deployment with the right
    // wiring; no proxy / no upgrade / no governance switch needed.
    // ─────────────────────────────────────────────────────────────────────
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    IPoolManager      public immutable poolManager;
    IPositionManager  public immutable positionManager;
    IStateView        public immutable stateView;
    IUniversalRouter  public immutable router;

    // ─────────────────────────────────────────────────────────────────────
    // Governance
    // ─────────────────────────────────────────────────────────────────────
    address public governor;
    address public pendingGovernor;

    // ─────────────────────────────────────────────────────────────────────
    // Registry, Hook, NFT
    // ─────────────────────────────────────────────────────────────────────
    ITokenRegistry public immutable REGISTRY;
    ITickrOwnerNFT public immutable TICKR_NFT;
    address public tickrHook;

    // Per-token snapshot of pool-determining fields at deploy time.
    // Packed: 20 + 3 = 23 bytes (1 slot, 9 bytes free for future PoolKey fields).
    struct TokenPoolInfo {
        address hook;
        int24 tickSpacing;
    }
    mapping(address => TokenPoolInfo) public tokenPoolInfo;

    // ─────────────────────────────────────────────────────────────────────
    // Liquidity configs
    // ─────────────────────────────────────────────────────────────────────
    struct LiquidityConfig {
        uint160 sqrtPriceX96;
        int24 tickLower;
        int24 tickUpper;
        int24 tickSpacing;
        uint256 amount1Desired;
        uint256 virtualAmount;
    }

    mapping(uint256 => LiquidityConfig) public liquidityConfigs;
    uint256 public liquidityConfigCount;

    // ─────────────────────────────────────────────────────────────────────
    // Token tracking (slim — no TokenInfo struct; indexer is event-driven)
    // ─────────────────────────────────────────────────────────────────────
    mapping(uint256 => address) public deployedTokens;     // index → address
    mapping(address => uint256) public tokenDeployedAt;    // address → timestamp
    mapping(address => address) public tokenCreator;       // address → original deployer
    uint256 public tokenCount;

    mapping(address => address[]) public creatorTokens;
    mapping(address => uint256) public tokenFeesGenerated;
    mapping(address => uint256) public lifetimeEarnedByCreator;

    bool public deployCoinEnabled = true;

    // ─────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────
    event TokenLaunched(
        address indexed tokenAddress,
        address indexed creator,
        uint256 indexed configId,
        bytes32 poolId,
        string name,
        string symbol,
        string metadata,
        uint256 timestamp
    );

    event LiquidityProvided(
        address indexed tokenAddress,
        bytes32 indexed poolId,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount1,
        uint128 liquidity
    );

    event TokenPurchased(
        address indexed buyer,
        address indexed tokenOut,
        uint256 ethSpent,
        uint256 tokensReceived
    );

    event FeesCollected(
        address indexed tokenAddress,
        address indexed creator,
        uint256 ethCollected
    );

    event CreatorChanged(
        address indexed tokenAddress,
        address indexed oldCreator,
        address indexed newCreator
    );

    event PlatformFeesWithdrawn(address indexed to, uint256 amount);

    event LiquidityConfigCreated(
        uint256 indexed configId,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing,
        uint256 amount1Desired,
        uint256 virtualAmount
    );

    event LiquidityConfigUpdated(
        uint256 indexed configId,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing,
        uint256 amount1Desired,
        uint256 virtualAmount
    );

    event LiquidityConfigDeleted(uint256 indexed configId);

    event GovernorTransferStarted(address indexed currentGovernor, address indexed pendingGovernor);
    event GovernorTransferred(address indexed previousGovernor, address indexed newGovernor);

    event TickrHookUpdated(address indexed oldHook, address indexed newHook);
    event DeployCoinToggled(bool enabled);

    // ─────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────
    modifier onlyGovernor() {
        require(msg.sender == governor, "Not governor");
        _;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────
    constructor(
        address _registry,
        address _tickrHook,
        address _tickrNFT,
        address _poolManager,
        address _positionManager,
        address _stateView,
        address _universalRouter
    ) {
        require(_registry != address(0), "Registry zero");
        require(_tickrHook != address(0), "Hook zero");
        require(_tickrNFT != address(0), "NFT zero");
        require(_poolManager != address(0), "PoolManager zero");
        require(_positionManager != address(0), "PositionManager zero");
        require(_stateView != address(0), "StateView zero");
        require(_universalRouter != address(0), "UniversalRouter zero");

        governor = msg.sender;
        REGISTRY = ITokenRegistry(_registry);
        TICKR_NFT = ITickrOwnerNFT(_tickrNFT);
        tickrHook = _tickrHook;

        poolManager = IPoolManager(_poolManager);
        positionManager = IPositionManager(_positionManager);
        stateView = IStateView(_stateView);
        router = IUniversalRouter(_universalRouter);

        emit GovernorTransferred(address(0), msg.sender);
        emit TickrHookUpdated(address(0), _tickrHook);

        // Default liquidity config (ID: 0) — single-sided launch, 1B token, ETH = currency0
        // Tier: 5 ETH initial FDV (~$11.4K @ ETH=$2287). 1 ETH ≈ 200M tokens at start.
        LiquidityConfig memory cfg = LiquidityConfig({
            sqrtPriceX96: 1120408587790087695236213992013890,
            tickLower: -887200,
            tickUpper: 191000,
            tickSpacing: 200,
            amount1Desired: 1_000_000_000 * 1e18,
            virtualAmount: 5 ether
        });
        liquidityConfigs[0] = cfg;
        liquidityConfigCount = 1;

        emit LiquidityConfigCreated(
            0,
            cfg.sqrtPriceX96,
            cfg.tickLower,
            cfg.tickUpper,
            cfg.tickSpacing,
            cfg.amount1Desired,
            cfg.virtualAmount
        );
    }

    receive() external payable {}  // Hook platform share lands here

    // ─────────────────────────────────────────────────────────────────────
    // Core: deployCoin
    // ─────────────────────────────────────────────────────────────────────
    function deployCoin(
        string memory _name,
        string memory _symbol,
        string memory _metadata,
        bytes32 salt,
        uint256 configId
    ) public payable nonReentrant returns (uint256 tokensReceived) {
        require(deployCoinEnabled, "Deploy disabled");
        require(configId < liquidityConfigCount, "Invalid config");

        // 1. Symbol register on registry (revert if taken/invalid/reserved).
        //    Cheapest fail point — runs before token deploy to save ~50K gas on collisions.
        REGISTRY.registerSymbol(_symbol);

        // 2. Token deploy (CREATE2)
        Token t = new Token{salt: salt}(_name, _symbol, msg.sender, address(this));
        address coin_address = address(t);

        // 3. Pool initialize + LP burn to dEaD
        bytes32 poolId = provideLiquidityV4(coin_address, configId);

        // 4. Mint Tickr Owner NFT to creator (1 NFT per ticker, links tokenId ↔ ticker).
        TICKR_NFT.mintFor(msg.sender, coin_address);

        // 5. Tracking (slim — no struct)
        deployedTokens[tokenCount] = coin_address;
        tokenDeployedAt[coin_address] = block.timestamp;
        tokenCreator[coin_address] = msg.sender;
        tokenPoolInfo[coin_address] = TokenPoolInfo({
            hook: tickrHook,
            tickSpacing: liquidityConfigs[configId].tickSpacing
        });
        creatorTokens[msg.sender].push(coin_address);
        tokenCount++;

        emit TokenLaunched(
            coin_address,
            msg.sender,
            configId,
            poolId,
            _name,
            _symbol,
            _metadata,
            block.timestamp
        );

        // 5. Optional initial buy — full msg.value goes to swap.
        //    Hook still takes 2% fee in beforeSwap (creator + platform shares).
        if (msg.value > 0) {
            uint256 tokensBefore = IERC20(coin_address).balanceOf(address(this));
            _buyToken(coin_address, msg.value);
            uint256 tokensAfter = IERC20(coin_address).balanceOf(address(this));
            tokensReceived = tokensAfter - tokensBefore;

            IERC20(coin_address).transfer(msg.sender, tokensReceived);
            emit TokenPurchased(msg.sender, coin_address, msg.value, tokensReceived);
        }

        return tokensReceived;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Pool initialization + LP mint to 0xdead
    // ─────────────────────────────────────────────────────────────────────
    function provideLiquidityV4(address tokenA, uint256 configId)
        internal
        returns (bytes32 poolIdBytes)
    {
        LiquidityConfig memory cfg = liquidityConfigs[configId];

        // Permit2 approval chain
        IERC20(tokenA).approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(tokenA, address(positionManager), type(uint160).max, type(uint48).max);
        PERMIT2.approve(tokenA, address(poolManager), type(uint160).max, type(uint48).max);

        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)),  // ETH always currency0
            currency1: Currency.wrap(tokenA),
            fee: 0,                                 // hook handles fees
            tickSpacing: cfg.tickSpacing,
            hooks: IHooks(tickrHook)
        });

        poolManager.initialize(pool, cfg.sqrtPriceX96);

        // Single-sided launch: position mints with currency1 (token) only.
        // sqrtPrice is initialized at tickUpper, so V4 math ignores amount0 and we
        // hardcode 0. No ETH is settled to PositionManager.
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            cfg.sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(cfg.tickLower),
            TickMath.getSqrtPriceAtTick(cfg.tickUpper),
            0,
            cfg.amount1Desired
        );

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            pool,
            cfg.tickLower,
            cfg.tickUpper,
            liquidity,
            uint256(0),          // max amount0 — single-sided, no ETH needed
            cfg.amount1Desired,
            address(0xdead),     // LP burned permanently — verifiable on-chain
            bytes("")            // hookData
        );
        params[1] = abi.encode(pool.currency0, pool.currency1);

        positionManager.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 120
        );

        poolIdBytes = keccak256(abi.encode(pool));

        emit LiquidityProvided(
            tokenA,
            poolIdBytes,
            cfg.sqrtPriceX96,
            cfg.tickLower,
            cfg.tickUpper,
            cfg.amount1Desired,
            liquidity
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    // Initial buy via Universal Router V4_SWAP
    // ─────────────────────────────────────────────────────────────────────
    function _buyToken(address tokenAddress, uint256 ethAmount) internal {
        TokenPoolInfo memory info = tokenPoolInfo[tokenAddress];
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(tokenAddress),
            fee: 0,
            tickSpacing: info.tickSpacing,
            hooks: IHooks(info.hook)
        });

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            pool,
            true,                       // zeroForOne: ETH → token
            uint128(ethAmount),
            uint128(0),                 // no slippage protection (atomic with deploy)
            bytes("")
        );
        params[1] = abi.encode(pool.currency0, ethAmount);
        params[2] = abi.encode(pool.currency1, uint128(0));

        inputs[0] = abi.encode(actions, params);

        router.execute{value: ethAmount}(commands, inputs, block.timestamp + 120);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Fee collection — creator or governor pulls token contract balance
    // ─────────────────────────────────────────────────────────────────────
    function collectFees(address tokenAddress) external nonReentrant returns (uint256 ethCollected) {
        address creator = Token(payable(tokenAddress)).creator();
        require(msg.sender == creator || msg.sender == governor, "Not authorized");

        uint256 balanceBefore = address(this).balance;
        Token(payable(tokenAddress)).withdrawFees();
        ethCollected = address(this).balance - balanceBefore;

        if (ethCollected > 0) {
            tokenFeesGenerated[tokenAddress] += ethCollected;
            lifetimeEarnedByCreator[creator] += ethCollected;

            (bool s, ) = payable(creator).call{value: ethCollected}("");
            require(s, "Creator transfer failed");

            emit FeesCollected(tokenAddress, creator, ethCollected);
        }
    }

    function collectFeesBatch(address[] calldata tokens)
        external nonReentrant
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            address creator = Token(payable(tokens[i])).creator();
            require(msg.sender == creator || msg.sender == governor, "Not authorized");

            uint256 before = address(this).balance;
            try Token(payable(tokens[i])).withdrawFees() returns (uint256) {
                amounts[i] = address(this).balance - before;
            } catch {
                // Token had no fees to withdraw — skip silently
                continue;
            }

            if (amounts[i] > 0) {
                tokenFeesGenerated[tokens[i]] += amounts[i];
                lifetimeEarnedByCreator[creator] += amounts[i];
                (bool s, ) = payable(creator).call{value: amounts[i]}("");
                require(s, "Transfer failed");
                emit FeesCollected(tokens[i], creator, amounts[i]);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Governor functions
    // ─────────────────────────────────────────────────────────────────────
    function setTickrHook(address _newHook) external onlyGovernor {
        require(_newHook != address(0), "Zero address");
        address oldHook = tickrHook;
        tickrHook = _newHook;
        emit TickrHookUpdated(oldHook, _newHook);
    }

    function toggleDeployCoin() external onlyGovernor {
        deployCoinEnabled = !deployCoinEnabled;
        emit DeployCoinToggled(deployCoinEnabled);
    }

    /// @notice Called by the Tickr Owner NFT contract on every NFT transfer (not mint/burn).
    ///         Settles any pending fees to the OLD creator first, then updates the on-chain
    ///         creator on the ticker token contract so future fees route to the new NFT holder.
    function syncCreator(address tokenAddress, address newCreator) external nonReentrant {
        require(msg.sender == address(TICKR_NFT), "Only NFT");
        require(newCreator != address(0), "Zero address");

        address oldCreator = Token(payable(tokenAddress)).creator();
        uint256 before = address(this).balance;
        try Token(payable(tokenAddress)).withdrawFees() returns (uint256) {
            uint256 collected = address(this).balance - before;
            if (collected > 0) {
                tokenFeesGenerated[tokenAddress] += collected;
                lifetimeEarnedByCreator[oldCreator] += collected;
                (bool s, ) = payable(oldCreator).call{value: collected}("");
                require(s, "Settle failed");
                emit FeesCollected(tokenAddress, oldCreator, collected);
            }
        } catch {
            // No fees to settle, proceed
        }

        Token(payable(tokenAddress)).changeCreator(newCreator);
        emit CreatorChanged(tokenAddress, oldCreator, newCreator);
    }

    function withdrawFeesETH() external nonReentrant onlyGovernor {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH");

        (bool s, ) = msg.sender.call{value: balance}("");
        require(s, "Transfer failed");

        emit PlatformFeesWithdrawn(msg.sender, balance);
    }

    // Liquidity config CRUD

    function createLiquidityConfig(
        uint160 _sqrtPriceX96,
        int24 _tickLower,
        int24 _tickUpper,
        int24 _tickSpacing,
        uint256 _amount1Desired,
        uint256 _virtualAmount
    ) external onlyGovernor returns (uint256 configId) {
        configId = liquidityConfigCount;
        liquidityConfigs[configId] = LiquidityConfig({
            sqrtPriceX96: _sqrtPriceX96,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            tickSpacing: _tickSpacing,
            amount1Desired: _amount1Desired,
            virtualAmount: _virtualAmount
        });
        liquidityConfigCount++;

        emit LiquidityConfigCreated(
            configId,
            _sqrtPriceX96,
            _tickLower,
            _tickUpper,
            _tickSpacing,
            _amount1Desired,
            _virtualAmount
        );
    }

    function updateLiquidityConfig(
        uint256 _configId,
        uint160 _sqrtPriceX96,
        int24 _tickLower,
        int24 _tickUpper,
        int24 _tickSpacing,
        uint256 _amount1Desired,
        uint256 _virtualAmount
    ) external onlyGovernor {
        require(_configId < liquidityConfigCount, "Invalid config ID");

        liquidityConfigs[_configId] = LiquidityConfig({
            sqrtPriceX96: _sqrtPriceX96,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            tickSpacing: _tickSpacing,
            amount1Desired: _amount1Desired,
            virtualAmount: _virtualAmount
        });

        emit LiquidityConfigUpdated(
            _configId,
            _sqrtPriceX96,
            _tickLower,
            _tickUpper,
            _tickSpacing,
            _amount1Desired,
            _virtualAmount
        );
    }

    function deleteLiquidityConfig(uint256 _configId) external onlyGovernor {
        require(_configId < liquidityConfigCount, "Invalid config ID");
        require(_configId != 0, "Cannot delete default config");

        delete liquidityConfigs[_configId];
        emit LiquidityConfigDeleted(_configId);
    }

    function getLiquidityConfig(uint256 _configId) external view returns (LiquidityConfig memory) {
        require(_configId < liquidityConfigCount, "Invalid config ID");
        return liquidityConfigs[_configId];
    }

    // 2-step governor transfer

    function transferGovernor(address newGovernor) external onlyGovernor {
        require(newGovernor != address(0), "Zero address");
        pendingGovernor = newGovernor;
        emit GovernorTransferStarted(governor, newGovernor);
    }

    function acceptGovernor() external {
        require(msg.sender == pendingGovernor, "Not pending governor");
        address oldGovernor = governor;
        governor = msg.sender;
        delete pendingGovernor;
        emit GovernorTransferred(oldGovernor, msg.sender);
    }

    // ─────────────────────────────────────────────────────────────────────
    // View / helper functions
    // ─────────────────────────────────────────────────────────────────────
    function getTokenBytecode(
        string memory _name,
        string memory _symbol,
        address creator
    ) public view returns (bytes memory) {
        return abi.encodePacked(
            type(Token).creationCode,
            abi.encode(_name, _symbol, creator, address(this))
        );
    }

    function predictTokenAddress(
        string memory _name,
        string memory _symbol,
        address creator,
        bytes32 salt
    ) public view returns (address) {
        bytes memory bytecode = getTokenBytecode(_name, _symbol, creator);
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode))
        );
        return address(uint160(uint256(hash)));
    }

    function getTokenPrice(address tokenAddress)
        public view
        returns (bytes32 poolIdBytes, uint160 sqrtPrice, uint256 priceWei, uint256 mcapETH)
    {
        TokenPoolInfo memory info = tokenPoolInfo[tokenAddress];
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(tokenAddress),
            fee: 0,
            tickSpacing: info.tickSpacing,
            hooks: IHooks(info.hook)
        });

        PoolId poolId = PoolId.wrap(keccak256(abi.encode(pool)));
        poolIdBytes = PoolId.unwrap(poolId);

        try stateView.getSlot0(poolId) returns (uint160 sp, int24, uint24, uint24) {
            sqrtPrice = sp;
            if (sp > 0) {
                uint256 spU = uint256(sp);
                uint256 q96 = 2**96;
                uint256 scaled = (q96 * 1e18) / spU;
                priceWei = (scaled * q96) / spU;
                uint256 supply = IERC20(tokenAddress).totalSupply();
                mcapETH = priceWei * supply / 1e18;
            }
        } catch {}
    }

    function getMarketCap(address tokenAddress) public view returns (uint256) {
        (,,, uint256 mcap) = getTokenPrice(tokenAddress);
        return mcap;
    }

    function getCreatorTokens(address creator) external view returns (address[] memory) {
        return creatorTokens[creator];
    }

    function getTokenFeesGenerated(address tokenAddress) external view returns (uint256) {
        return tokenFeesGenerated[tokenAddress];
    }

    function isTokenDeployed(address tokenAddress) external view returns (bool) {
        return tokenCreator[tokenAddress] != address(0);
    }
}
