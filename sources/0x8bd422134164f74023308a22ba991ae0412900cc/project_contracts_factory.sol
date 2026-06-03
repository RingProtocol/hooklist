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

import "./token.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IToken {
    function creator() external view returns (address);
    function burn(uint256 amount) external;
}

interface IWETH {
    function withdraw(uint256 amount) external;
}

interface IUniswapV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
}

interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

contract Factory is ReentrancyGuard {
    event TokenLaunched(
        address indexed tokenAddress,
        address indexed creator,
        uint256 indexed configId,
        uint256 nftId,
        address pool,
        string name,
        string symbol,
        string metadata,
        uint256 timestamp
    );

    struct TokenInfo {
        address tokenAddress;
        string name;
        string symbol;
        address deployer;
        uint256 time;
        string metadata;
        uint256 nftId;
        uint256 tokenBalance;
        uint256 totalFeesGenerated;
    }

    mapping(uint256 => TokenInfo) public deployedTokens;
    mapping(address => TokenInfo) public tokenInfoByAddress;
    uint256 public tokenCount = 0;
    address public governor;
    address public pendingGovernor;

    mapping(address => uint256) public tokenFeesGenerated;
    mapping(address => uint256) public lifetimeEarnedByCreator;
    mapping(string => bool) public symbolTaken;
    
    // Mapping to store NFT ID for each token
    // tokenAddress => NFT tokenId
    mapping(address => uint256) public tokenToNFTId;
    
    // Liquidity configuration struct
    struct LiquidityConfig {
        uint160 sqrtPriceX96A;  // sqrtPriceX96 when tokenA is token0
        uint160 sqrtPriceX96B;  // sqrtPriceX96 when tokenA is token1
        int24 tickLower;        // Lower tick for the position
        int24 tickUpper;        // Upper tick for the position
        uint256 amount0Desired; // Desired amount of token0
        uint256 amount1Desired; // Desired amount of token1
        uint256 virtualAmount;  // Virtual amount for market cap calculation
    }
    
    // Multiple liquidity configurations
    mapping(uint256 => LiquidityConfig) public liquidityConfigs;
    uint256 public liquidityConfigCount = 0;

    address public constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant SWAP_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45; // SwapRouter02

    uint24 private constant FEE_TIER = 10000;

    event TokenPurchased(
        address indexed buyer,
        address indexed tokenOut,
        uint256 ethSpent,
        uint256 tokensReceived
    );
    event LiquidityProvided(
        address indexed tokenAddress,
        uint256 indexed nftId,
        address indexed pool,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    );
    event FeesCollected(
        address indexed tokenAddress,
        uint256 indexed nftId,
        address indexed creator,
        uint256 collected0,
        uint256 collected1,
        uint256 burnedAmount,
        uint256 creatorEthShare,
        uint256 platformEthShare
    );
    event CreatorChanged(
        address indexed tokenAddress,
        address indexed oldCreator,
        address indexed newCreator
    );
    event PlatformFeesWithdrawn(
        address indexed to,
        uint256 amount,
        bool fromWeth
    );
    event LiquidityConfigCreated(
        uint256 indexed configId,
        uint160 sqrtPriceX96A,
        uint160 sqrtPriceX96B,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 virtualAmount
    );
    event LiquidityConfigUpdated(
        uint256 indexed configId,
        uint160 sqrtPriceX96A,
        uint160 sqrtPriceX96B,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 virtualAmount
    );
    event LiquidityConfigDeleted(uint256 indexed configId);
    event GovernorTransferStarted(address indexed currentGovernor, address indexed pendingGovernor);
    event GovernorTransferred(address indexed previousGovernor, address indexed newGovernor);

    modifier onlyGovernor() {
        require(msg.sender == governor, "Not governor");
        _;
    }

    constructor() {
        governor = msg.sender;
        emit GovernorTransferred(address(0), msg.sender);

        // Initialize default liquidity configuration (ID: 0)
        LiquidityConfig memory cfg = LiquidityConfig({
            sqrtPriceX96A: 3068365595550320841079178,
            sqrtPriceX96B: 2045645379722529521098596513701367,
            tickLower: 203000,
            tickUpper: 887200,
            amount0Desired: 1000000000000000000000000000,
            amount1Desired: 0,
            virtualAmount: 1.5 ether
        });
        liquidityConfigs[0] = cfg;
        liquidityConfigCount = 1;

        emit LiquidityConfigCreated(
            0,
            cfg.sqrtPriceX96A,
            cfg.sqrtPriceX96B,
            cfg.tickLower,
            cfg.tickUpper,
            cfg.amount0Desired,
            cfg.amount1Desired,
            cfg.virtualAmount
        );
    }

    receive() external payable {} // for collectFees

    function deployCoin(
        string memory _name,
        string memory _symbol,
        string memory _metadata,
        bytes32 salt,
        uint256 configId
    ) public payable nonReentrant returns (uint256 tokensReceived) {
        require(configId < liquidityConfigCount, "Invalid liquidity config ID");
        require(_isValidSymbol(_symbol), "Symbol: [a-z A-Z 0-9] only, min 1 char");
        require(!symbolTaken[_symbol], "Symbol already taken");
        symbolTaken[_symbol] = true;

        Token t = new Token{salt: salt}(
            _name,
            _symbol,
            msg.sender,
            address(this)
        );

        address coin_address = address(t);
        (uint256 nftId, address pool) = provideLiquidity(coin_address, WETH, configId);

        emit TokenLaunched(
            coin_address,
            msg.sender,
            configId,
            nftId,
            pool,
            _name,
            _symbol,
            _metadata,
            block.timestamp
        );

        tokensReceived = 0;

        if (msg.value > 0) {
            ISwapRouter02(SWAP_ROUTER).exactInputSingle{ value: msg.value }(
                ISwapRouter02.ExactInputSingleParams({
                    tokenIn: WETH,
                    tokenOut: coin_address,
                    fee: FEE_TIER,
                    recipient: address(this),
                    amountIn: msg.value,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );

            IERC20 token = IERC20(coin_address);
            tokensReceived = token.balanceOf(address(this));
            token.transfer(msg.sender, tokensReceived);

            emit TokenPurchased(msg.sender, coin_address, msg.value, tokensReceived);
        }

        TokenInfo memory newTokenInfo = TokenInfo({
            tokenAddress: coin_address,
            name: _name,
            symbol: _symbol,
            deployer: msg.sender,
            time: block.timestamp,
            metadata: _metadata,
            nftId: tokenToNFTId[coin_address],
            tokenBalance: 0,
            totalFeesGenerated: 0
        });

        deployedTokens[tokenCount] = newTokenInfo;
        tokenInfoByAddress[coin_address] = newTokenInfo;

        tokenCount++;

        return tokensReceived;
    }

    function getTokenBytecode(
        string memory _name,
        string memory _symbol,
        address creator
    ) public view returns (bytes memory bytecode) {
        bytecode = abi.encodePacked(
            type(Token).creationCode,
            abi.encode(_name, _symbol, creator, address(this))
        );
    }

    // Simulate the CREATE2 address that deployCoin would produce
    // _deployer = the address that will call deployCoin (used as Token.creator)
    function predictTokenAddress(
        string memory _name,
        string memory _symbol,
        address _deployer,
        bytes32 salt
    ) public view returns (address predicted) {
        bytes memory bytecode = getTokenBytecode(_name, _symbol, _deployer);
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode))
        );
        predicted = address(uint160(uint256(hash)));
    }

    function withdrawFeesWETH() external nonReentrant onlyGovernor {
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        require(wethBalance > 0, "No WETH to withdraw");

        IWETH(WETH).withdraw(wethBalance);

        (bool success, ) = msg.sender.call{ value: wethBalance }("");
        require(success, "ETH transfer failed");

        emit PlatformFeesWithdrawn(msg.sender, wethBalance, true);
    }

    function withdrawFeesETH() external nonReentrant onlyGovernor {
        uint256 ethBalance = address(this).balance;
        require(ethBalance > 0, "No ETH to withdraw");

        (bool success, ) = msg.sender.call{ value: ethBalance }("");
        require(success, "ETH transfer failed");

        emit PlatformFeesWithdrawn(msg.sender, ethBalance, false);
    }
    
    // Create new liquidity configuration
    function createLiquidityConfig(
        uint160 _sqrtPriceX96A,
        uint160 _sqrtPriceX96B,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0Desired,
        uint256 _amount1Desired,
        uint256 _virtualAmount
    ) external onlyGovernor returns (uint256 configId) {
        configId = liquidityConfigCount;
        liquidityConfigs[configId] = LiquidityConfig({
            sqrtPriceX96A: _sqrtPriceX96A,
            sqrtPriceX96B: _sqrtPriceX96B,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            amount0Desired: _amount0Desired,
            amount1Desired: _amount1Desired,
            virtualAmount: _virtualAmount
        });
        liquidityConfigCount++;

        emit LiquidityConfigCreated(
            configId,
            _sqrtPriceX96A,
            _sqrtPriceX96B,
            _tickLower,
            _tickUpper,
            _amount0Desired,
            _amount1Desired,
            _virtualAmount
        );

        return configId;
    }

    // Update existing liquidity configuration
    function updateLiquidityConfig(
        uint256 _configId,
        uint160 _sqrtPriceX96A,
        uint160 _sqrtPriceX96B,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0Desired,
        uint256 _amount1Desired,
        uint256 _virtualAmount
    ) external onlyGovernor {
        require(_configId < liquidityConfigCount, "Invalid config ID");

        liquidityConfigs[_configId] = LiquidityConfig({
            sqrtPriceX96A: _sqrtPriceX96A,
            sqrtPriceX96B: _sqrtPriceX96B,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            amount0Desired: _amount0Desired,
            amount1Desired: _amount1Desired,
            virtualAmount: _virtualAmount
        });

        emit LiquidityConfigUpdated(
            _configId,
            _sqrtPriceX96A,
            _sqrtPriceX96B,
            _tickLower,
            _tickUpper,
            _amount0Desired,
            _amount1Desired,
            _virtualAmount
        );
    }

    // Delete liquidity configuration (sets to zero values)
    function deleteLiquidityConfig(uint256 _configId) external onlyGovernor {
        require(_configId < liquidityConfigCount, "Invalid config ID");
        require(_configId != 0, "Cannot delete default config");

        delete liquidityConfigs[_configId];
        emit LiquidityConfigDeleted(_configId);
    }
    
    // Get liquidity configuration
    function getLiquidityConfig(uint256 _configId) external view returns (LiquidityConfig memory) {
        require(_configId < liquidityConfigCount, "Invalid config ID");
        return liquidityConfigs[_configId];
    }


    function provideLiquidity(address tokenA, address tokenB, uint256 configId)
        internal
        returns (uint256 tokenId, address pool)
    {
        LiquidityConfig memory config = liquidityConfigs[configId];
        bool tokenAIsToken0 = tokenA < tokenB;

        address token0 = tokenAIsToken0 ? tokenA : tokenB;
        address token1 = tokenAIsToken0 ? tokenB : tokenA;

        IERC20(token0).approve(POSITION_MANAGER, type(uint256).max);
        IERC20(token1).approve(POSITION_MANAGER, type(uint256).max);

        INonfungiblePositionManager manager = INonfungiblePositionManager(POSITION_MANAGER);

        uint160 sqrtPriceX96 = tokenAIsToken0
            ? config.sqrtPriceX96A
            : config.sqrtPriceX96B;

        int24 tickLower = tokenAIsToken0 ? -config.tickLower : -config.tickUpper;
        int24 tickUpper = tokenAIsToken0 ? config.tickUpper : config.tickLower;

        uint256 amount0Desired = tokenAIsToken0 ? config.amount0Desired : config.amount1Desired;
        uint256 amount1Desired = tokenAIsToken0 ? config.amount1Desired : config.amount0Desired;

        pool = manager.createAndInitializePoolIfNecessary(token0, token1, FEE_TIER, sqrtPriceX96);

        uint256 amount0Used;
        uint256 amount1Used;
        (tokenId, , amount0Used, amount1Used) = manager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: FEE_TIER,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        _storeNFTId(tokenA, tokenId);

        emit LiquidityProvided(
            tokenA,
            tokenId,
            pool,
            sqrtPriceX96,
            tickLower,
            tickUpper,
            amount0Used,
            amount1Used
        );
    }
    
    function collectFees(uint256 tokenId) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        (
            , , address token0Raw, address token1Raw, , , , , , , ,
        ) = INonfungiblePositionManager(POSITION_MANAGER).positions(tokenId);

        address token0 = (token0Raw == WETH && token1Raw != WETH) ? token1Raw : token0Raw;
        address creator = IToken(token0).creator();
        require(msg.sender == creator || msg.sender == governor, "Not authorized");

        return _collectFeesInternal(tokenId);
    }

    function collectFeesBatch(uint256[] calldata tokenIds)
        external
        nonReentrant
        returns (uint256[] memory amount0s, uint256[] memory amount1s)
    {
        uint256 n = tokenIds.length;
        amount0s = new uint256[](n);
        amount1s = new uint256[](n);

        bool isGovernor = msg.sender == governor;

        for (uint256 i = 0; i < n; i++) {
            if (!isGovernor) {
                (
                    , , address token0Raw, address token1Raw, , , , , , , ,
                ) = INonfungiblePositionManager(POSITION_MANAGER).positions(tokenIds[i]);
                address token0 = (token0Raw == WETH && token1Raw != WETH) ? token1Raw : token0Raw;
                require(msg.sender == IToken(token0).creator(), "Not authorized");
            }
            (amount0s[i], amount1s[i]) = _collectFeesInternal(tokenIds[i]);
        }
    }

    function _collectFeesInternal(uint256 tokenId) internal returns (uint256 collected0, uint256 collected1) {
        (
            , , address token0Raw, address token1Raw, , , , , , , ,
        ) = INonfungiblePositionManager(POSITION_MANAGER).positions(tokenId);

        address token0 = token0Raw;
        address token1 = token1Raw;
        if (token0Raw == WETH && token1Raw != WETH) {
            token0 = token1Raw;
            token1 = token0Raw;
        }
        require(token1 == WETH, "token1 must be WETH");

        address creator = IToken(token0).creator();

        uint256 beforeToken0 = IERC20(token0).balanceOf(address(this));
        uint256 beforeToken1 = IERC20(token1).balanceOf(address(this));

        INonfungiblePositionManager(POSITION_MANAGER).collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        collected0 = IERC20(token0).balanceOf(address(this)) - beforeToken0;
        collected1 = IERC20(token1).balanceOf(address(this)) - beforeToken1;

        uint256 burnedAmount;
        uint256 creatorAmount;
        uint256 platformAmount;

        if (collected0 > 0) {
            IToken(token0).burn(collected0);
            burnedAmount = collected0;
        }

        if (collected1 > 0) {
            IWETH(token1).withdraw(collected1);
            platformAmount = collected1 / 2;
            creatorAmount = collected1 - platformAmount;
            if (creatorAmount > 0) {
                _transferETH(creator, creatorAmount);
                _trackTokenFees(token0, creatorAmount);
                lifetimeEarnedByCreator[creator] += creatorAmount;
            }
        }

        emit FeesCollected(
            token0,
            tokenId,
            creator,
            collected0,
            collected1,
            burnedAmount,
            creatorAmount,
            platformAmount
        );
    }

    function changeTokenCreator(address tokenAddress, address newCreator) external nonReentrant onlyGovernor {
        require(newCreator != address(0), "New creator cannot be zero address");

        // Settle pending fees to current creator before swapping
        uint256 nftId = tokenToNFTId[tokenAddress];
        if (nftId != 0) {
            _collectFeesInternal(nftId);
        }

        address oldCreator = Token(tokenAddress).creator();
        Token(tokenAddress).changeCreator(newCreator);
        emit CreatorChanged(tokenAddress, oldCreator, newCreator);
    }

    // Two-step governor transfer. Current governor proposes; the new address must
    // accept to take over, preventing accidental loss to a wrong/typo'd address.
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
    
    
    // Get total fees generated by a specific token
    function getTokenFeesGenerated(address tokenAddress) public view returns (uint256) {
        return tokenFeesGenerated[tokenAddress];
    }
    
    // Helper function to transfer ETH and handle failures
    function _transferETH(address recipient, uint256 amount) internal {
        (bool success, ) = payable(recipient).call{value: amount}("");
        require(success, "ETH transfer failed");
    }
    
    // Helper function to track fees generated by a token
    function _trackTokenFees(address token, uint256 amount) internal {
        tokenFeesGenerated[token] += amount;
    }
    
    // Helper function to store NFT ID for a token
    function _storeNFTId(address token, uint256 nftId) internal {
        tokenToNFTId[token] = nftId;
    }

    /// @dev Symbol must be at least 1 byte and contain only [a-z A-Z 0-9].
    /// Catches non-ASCII (multi-byte UTF-8) implicitly because every byte
    /// of such a sequence falls outside the alphanumeric ASCII ranges.
    function _isValidSymbol(string memory s) internal pure returns (bool) {
        bytes memory b = bytes(s);
        uint256 len = b.length;
        if (len == 0) return false;
        for (uint256 i = 0; i < len; i++) {
            bytes1 c = b[i];
            // 0x30-0x39 = '0'-'9', 0x41-0x5A = 'A'-'Z', 0x61-0x7A = 'a'-'z'
            if (
                !(c >= 0x30 && c <= 0x39) &&
                !(c >= 0x41 && c <= 0x5A) &&
                !(c >= 0x61 && c <= 0x7A)
            ) {
                return false;
            }
        }
        return true;
    }

    // Returns the price of 1 whole token in wei of ETH.
    // Frontend: formatEther(priceWei) -> ETH per token.
    function getTokenPriceInWei(address tokenAddress) public view returns (uint256 priceWei) {
        address pool = IUniswapV3Factory(
            INonfungiblePositionManager(POSITION_MANAGER).factory()
        ).getPool(tokenAddress, WETH, FEE_TIER);
        if (pool == address(0)) return 0;

        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
        if (sqrtPriceX96 == 0) return 0;

        // Shift sqrtPrice down by 32 bits before squaring to avoid uint256 overflow
        // at extreme prices. priceWei = sqrtPrice^2 * 1e18 / 2^192
        uint256 sp = uint256(sqrtPriceX96) >> 32;
        uint256 sq = sp * sp; // (sqrtPrice/2^32)^2 = sqrtPrice^2 / 2^64

        if (tokenAddress < WETH) {
            // token = token0: price (WETH per token, raw) = sqrtPrice^2 / 2^192
            priceWei = (sq * 1e18) >> 128;
        } else {
            // token = token1: price (WETH per token, raw) = 2^192 / sqrtPrice^2
            if (sq == 0) return 0;
            priceWei = (uint256(1e18) << 128) / sq;
        }
    }

    // Fully Diluted Valuation in wei: price * initial supply (1B tokens).
    function getTokenFDV(address tokenAddress) external view returns (uint256 fdvWei) {
        return getTokenPriceInWei(tokenAddress) * 1_000_000_000;
    }

    /// @notice Preview the ETH a creator would receive if collectFeesBatch were called now.
    /// @dev Reads positions' last-settled tokensOwed. Newly-accrued fees that haven't
    ///      been "poked" (no recent collect/mint/decreaseLiquidity) won't be reflected.
    ///      For perfect accuracy frontends can use simulateContract on collectFeesBatch.
    /// @param tokenIds NFT position ids (typically from tokenToNFTId mapping).
    /// @return totalEth Sum of creator-share ETH across all positions.
    /// @return perTokenEth Per-tokenId creator-share ETH (parallel to tokenIds).
    function previewClaimableETH(uint256[] calldata tokenIds)
        external
        view
        returns (uint256 totalEth, uint256[] memory perTokenEth)
    {
        uint256 n = tokenIds.length;
        perTokenEth = new uint256[](n);

        for (uint256 i = 0; i < n; i++) {
            (
                , , address token0Raw, address token1Raw, , , , , , , uint128 tokensOwed0, uint128 tokensOwed1
            ) = INonfungiblePositionManager(POSITION_MANAGER).positions(tokenIds[i]);

            uint256 wethOwed;
            if (token0Raw == WETH) {
                wethOwed = uint256(tokensOwed0);
            } else if (token1Raw == WETH) {
                wethOwed = uint256(tokensOwed1);
            } else {
                continue;
            }

            // Creator share matches _collectFeesInternal: wethOwed - wethOwed/2 (ceil-half)
            uint256 creatorShare = wethOwed - (wethOwed / 2);
            perTokenEth[i] = creatorShare;
            totalEth += creatorShare;
        }
    }
}