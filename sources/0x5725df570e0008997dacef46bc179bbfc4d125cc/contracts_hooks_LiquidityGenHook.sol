// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../interfaces/IPoolManager.sol";
import "../interfaces/IHooks.sol";
import "../interfaces/ICurrency.sol";
import "../interfaces/IUnlockCallback.sol";
import "../interfaces/IConfigurableHook.sol";
import "../interfaces/IWETH.sol";
import "../libraries/LiquidityMath.sol";
import "../errors/Errors.sol";

contract LiquidityGenHook is IHooks, IConfigurableHook, IUnlockCallback {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;

    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant MAX_TAX_BPS = 1500;
    uint256 public constant MIN_PLATFORM_FEE_BPS = 2000;
    uint256 public constant MAX_PLATFORM_FEE_BPS = 5000;
    uint256 public constant MIN_THRESHOLD = 0.01 ether;
    uint256 public constant MAX_THRESHOLD = 1 ether;
    int24 public constant FULL_RANGE_LOWER = -887220;
    int24 public constant FULL_RANGE_UPPER = 887220;
    uint256 public constant MIN_GAS_FOR_LIQUIDITY = 350000;

    address public immutable poolManager;
    address public immutable weth;
    address public controller;
    address public platformFeeCollector;
    address public factory;
    uint256 public defaultPlatformFeeBps;

    struct LiquidityConfig {
        uint16 buyTaxBps;
        uint16 sellTaxBps;
        uint16 platformFeeBps;
        uint256 threshold;
        uint256 accumulated;
        address tokenAddress;
        bool enabled;
    }

    mapping(bytes32 => LiquidityConfig) public liquidityConfigs;

    uint256 public totalLiquidityAdded;
    uint256 public totalLiquidityEvents;
    uint256 public totalPlatformFees;

    bool private _liquidityInProgress;

    event TaxTaken(bytes32 indexed poolId, uint256 amount, bool isBuy);
    event LiquidityAdded(bytes32 indexed poolId, uint256 wethAmount, uint256 tokenAmount, uint128 liquidity);
    event PlatformFeeSent(bytes32 indexed poolId, uint256 wethAmount, address recipient);
    event ThresholdReached(bytes32 indexed poolId, uint256 accumulated);
    event PlatformFeeCollectorUpdated(address oldCollector, address newCollector);
    event PlatformFeeBpsUpdated(uint256 oldBps, uint256 newBps);
    event HookConfigured(bytes32 indexed poolId, address indexed token, uint16 buyTaxBps, uint16 sellTaxBps);
    event EmergencyWithdraw(address indexed to, uint256 wethAmount, uint256 ethAmount);
    event AutoLiquidityTriggered(bytes32 indexed poolId, uint256 gasRemaining);
    event AutoLiquiditySkipped(bytes32 indexed poolId, string reason);
    event ResidualsBurned(bytes32 indexed poolId, uint256 tokensBurned, uint256 wethRecycled);

    constructor(address _poolManager, address _weth, address _controller, address _platformFeeCollector) {
        poolManager = _poolManager;
        weth = _weth;
        controller = _controller;
        platformFeeCollector = _platformFeeCollector;
        defaultPlatformFeeBps = 2000;
    }

    function configureHook(
        bytes32 poolId,
        address tokenAddress,
        bytes calldata config
    ) external override {
        if (msg.sender != controller && msg.sender != factory) revert NotController();
        if (liquidityConfigs[poolId].enabled) revert HookAlreadyConfigured();

        (uint16 buyTaxBps, uint16 sellTaxBps, uint256 threshold) = abi.decode(config, (uint16, uint16, uint256));

        if (buyTaxBps > MAX_TAX_BPS) revert InvalidTaxRate();
        if (sellTaxBps > MAX_TAX_BPS) revert InvalidTaxRate();
        if (threshold < MIN_THRESHOLD || threshold > MAX_THRESHOLD) revert InvalidThreshold();

        liquidityConfigs[poolId] = LiquidityConfig({
            buyTaxBps: buyTaxBps,
            sellTaxBps: sellTaxBps,
            platformFeeBps: uint16(defaultPlatformFeeBps),
            threshold: threshold,
            accumulated: 0,
            tokenAddress: tokenAddress,
            enabled: true
        });

        emit HookConfigured(poolId, tokenAddress, buyTaxBps, sellTaxBps);
    }

    function getPoolId(PoolKey calldata key) external pure override returns (bytes32) {
        return _getPoolId(key);
    }

    function isConfigured(bytes32 poolId) external view override returns (bool) {
        return liquidityConfigs[poolId].enabled;
    }

    function setController(address newController) external {
        if (msg.sender != controller) revert NotController();
        if (newController == address(0)) revert InvalidReceiver();
        controller = newController;
    }

    function setFactory(address newFactory) external {
        if (msg.sender != controller) revert NotController();
        factory = newFactory;
    }

    function setPlatformFeeCollector(address newCollector) external {
        if (msg.sender != controller) revert NotController();
        if (newCollector == address(0)) revert InvalidReceiver();
        address oldCollector = platformFeeCollector;
        platformFeeCollector = newCollector;
        emit PlatformFeeCollectorUpdated(oldCollector, newCollector);
    }

    function setDefaultPlatformFeeBps(uint256 newPlatformFeeBps) external {
        if (msg.sender != controller) revert NotController();
        if (newPlatformFeeBps < MIN_PLATFORM_FEE_BPS || newPlatformFeeBps > MAX_PLATFORM_FEE_BPS) {
            revert InvalidConfig();
        }
        uint256 oldBps = defaultPlatformFeeBps;
        defaultPlatformFeeBps = newPlatformFeeBps;
        emit PlatformFeeBpsUpdated(oldBps, newPlatformFeeBps);
    }

    function emergencyWithdraw(bool withdrawETH) external {
        if (msg.sender != controller) revert NotController();

        uint256 wethBalance = IERC20(weth).balanceOf(address(this));
        uint256 ethBalance = address(this).balance;

        if (wethBalance > 0) {
            if (withdrawETH) {
                IWETH(weth).withdraw(wethBalance);
                ethBalance += wethBalance;
            } else {
                IERC20(weth).safeTransfer(controller, wethBalance);
            }
        }

        if (ethBalance > 0) {
            (bool success,) = payable(controller).call{value: ethBalance}("");
            require(success, "ETH transfer failed");
        }

        emit EmergencyWithdraw(controller, wethBalance, ethBalance);
    }

    function getHookPermissions() external pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeInitialize(address, PoolKey calldata, uint160) external pure returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external pure returns (bytes4)
    {
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata)
        external pure returns (bytes4, BalanceDelta)
    {
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external pure returns (bytes4)
    {
        return IHooks.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata)
        external pure returns (bytes4, BalanceDelta)
    {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) external returns (bytes4, BeforeSwapDelta, uint24) {
        if (msg.sender != poolManager) revert Unauthorized();

        bytes32 poolId = _getPoolId(key);
        LiquidityConfig storage config = liquidityConfigs[poolId];

        if (!config.enabled || _liquidityInProgress) {
            return (IHooks.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
        }

        address currency1Addr = Currency.unwrap(key.currency1);
        bool wethIsCurrency1 = currency1Addr == weth;

        bool isBuy;
        if (wethIsCurrency1) {
            isBuy = !params.zeroForOne;
        } else {
            isBuy = params.zeroForOne;
        }

        if (isBuy) {
            uint16 taxBps = config.buyTaxBps;
            if (taxBps == 0) {
                return (IHooks.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
            }

            uint256 wethAmount;
            if (params.amountSpecified < 0) {
                wethAmount = uint256(uint128(-int128(params.amountSpecified)));
            } else {
                wethAmount = uint256(uint128(int128(params.amountSpecified)));
            }

            uint256 feeAmount = (wethAmount * taxBps) / FEE_DENOMINATOR;

            if (feeAmount > 0) {
                Currency wethCurrency = wethIsCurrency1 ? key.currency1 : key.currency0;
                IPoolManager(poolManager).take(wethCurrency, address(this), feeAmount);

                config.accumulated += feeAmount;
                emit TaxTaken(poolId, feeAmount, true);

                bool exactInput = params.amountSpecified < 0;
                int128 specifiedDelta = exactInput ? int128(uint128(feeAmount)) : int128(0);
                int128 unspecifiedDelta = exactInput ? int128(0) : int128(uint128(feeAmount));

                BeforeSwapDelta hookDelta = BeforeSwapDelta.wrap(
                    int256(int128(specifiedDelta)) << 128 | int256(int128(unspecifiedDelta))
                );

                return (IHooks.beforeSwap.selector, hookDelta, 0);
            }
        }

        return (IHooks.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external returns (bytes4, int128) {
        if (msg.sender != poolManager) revert Unauthorized();

        bytes32 poolId = _getPoolId(key);
        LiquidityConfig storage config = liquidityConfigs[poolId];

        if (!config.enabled || _liquidityInProgress) {
            return (IHooks.afterSwap.selector, 0);
        }

        address currency1Addr = Currency.unwrap(key.currency1);
        bool wethIsCurrency1 = currency1Addr == weth;

        bool isSell;
        if (wethIsCurrency1) {
            isSell = params.zeroForOne;
        } else {
            isSell = !params.zeroForOne;
        }

        int128 hookDelta = 0;

        if (isSell && config.sellTaxBps > 0) {
            int128 amount0 = int128(int256(BalanceDelta.unwrap(delta)) >> 128);
            int128 amount1 = int128(int256(BalanceDelta.unwrap(delta)));

            int128 wethDelta = wethIsCurrency1 ? amount1 : amount0;

            uint256 wethOutput;
            if (wethDelta > 0) {
                wethOutput = uint256(uint128(wethDelta));
            } else if (wethDelta < 0) {
                wethOutput = uint256(uint128(-wethDelta));
            } else {
                wethOutput = 0;
            }

            if (wethOutput > 0) {
                uint256 feeAmount = (wethOutput * config.sellTaxBps) / FEE_DENOMINATOR;

                if (feeAmount > 0) {
                    Currency wethCurrency = wethIsCurrency1 ? key.currency1 : key.currency0;
                    IPoolManager(poolManager).take(wethCurrency, address(this), feeAmount);

                    config.accumulated += feeAmount;
                    emit TaxTaken(poolId, feeAmount, false);

                    hookDelta = int128(uint128(feeAmount));
                }
            }
        }

        if (config.accumulated >= config.threshold) {
            emit ThresholdReached(poolId, config.accumulated);

            if (!_liquidityInProgress && gasleft() >= MIN_GAS_FOR_LIQUIDITY) {
                emit AutoLiquidityTriggered(poolId, gasleft());
                _executeAutoLiquidity(key, poolId, config);
            } else if (_liquidityInProgress) {
                emit AutoLiquiditySkipped(poolId, "reentrancy");
            } else {
                emit AutoLiquiditySkipped(poolId, "insufficient gas");
            }
        }

        return (IHooks.afterSwap.selector, hookDelta);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external pure returns (bytes4)
    {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external pure returns (bytes4)
    {
        return IHooks.afterDonate.selector;
    }

    function _executeAutoLiquidity(
        PoolKey calldata key,
        bytes32 poolId,
        LiquidityConfig storage config
    ) internal {
        _liquidityInProgress = true;

        uint256 wethBalance = IERC20(weth).balanceOf(address(this));
        if (wethBalance == 0) {
            _liquidityInProgress = false;
            return;
        }

        uint256 totalAmount = wethBalance < config.accumulated ? wethBalance : config.accumulated;
        config.accumulated = config.accumulated > totalAmount ? config.accumulated - totalAmount : 0;

        uint256 platformFee = (totalAmount * config.platformFeeBps) / FEE_DENOMINATOR;
        uint256 liquidityBudget = totalAmount - platformFee;

        if (platformFee > 0 && platformFeeCollector != address(0)) {
            IWETH(weth).withdraw(platformFee);
            (bool success, ) = payable(platformFeeCollector).call{value: platformFee}("");
            require(success, "Platform fee transfer failed");
            totalPlatformFees += platformFee;
            emit PlatformFeeSent(poolId, platformFee, platformFeeCollector);
        }

        if (liquidityBudget > 0) {
            address currency1Addr = Currency.unwrap(key.currency1);
            bool wethIsCurrency1 = currency1Addr == weth;
            Currency wethCurrency = wethIsCurrency1 ? key.currency1 : key.currency0;
            Currency tokenCurrency = wethIsCurrency1 ? key.currency0 : key.currency1;

            uint256 wethForTokenBuy = liquidityBudget / 2;
            uint256 wethForLiquidity = liquidityBudget - wethForTokenBuy;

            bool zeroForOne = !wethIsCurrency1;

            SwapParams memory swapParams = SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(wethForTokenBuy),
                sqrtPriceLimitX96: zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970341
            });

            BalanceDelta swapDelta = IPoolManager(poolManager).swap(key, swapParams, "");

            int128 swapAmount0 = int128(int256(BalanceDelta.unwrap(swapDelta)) >> 128);
            int128 swapAmount1 = int128(int256(BalanceDelta.unwrap(swapDelta)));

            int128 wethSwapDelta = wethIsCurrency1 ? swapAmount1 : swapAmount0;
            int128 tokenSwapDelta = wethIsCurrency1 ? swapAmount0 : swapAmount1;

            if (wethSwapDelta < 0) {
                uint256 wethOwed = uint256(uint128(-wethSwapDelta));
                IPoolManager(poolManager).sync(wethCurrency);
                IERC20(weth).safeTransfer(poolManager, wethOwed);
                IPoolManager(poolManager).settle();
            }

            uint256 tokensReceived = 0;
            if (tokenSwapDelta > 0) {
                tokensReceived = uint256(uint128(tokenSwapDelta));
                IPoolManager(poolManager).take(tokenCurrency, address(this), tokensReceived);
            }

            if (wethForLiquidity > 0 && tokensReceived > 0) {
                uint256 amount0Desired;
                uint256 amount1Desired;
                if (wethIsCurrency1) {
                    amount0Desired = tokensReceived;
                    amount1Desired = wethForLiquidity;
                } else {
                    amount0Desired = wethForLiquidity;
                    amount1Desired = tokensReceived;
                }

                uint256 product = amount0Desired * amount1Desired;
                uint128 liquidity = uint128((_sqrt(product) * 95) / 100);

                if (liquidity > 0) {
                    bytes32 positionSalt = keccak256(abi.encodePacked(poolId, "LiquidityGenHook"));

                    ModifyLiquidityParams memory liqParams = ModifyLiquidityParams({
                        tickLower: FULL_RANGE_LOWER,
                        tickUpper: FULL_RANGE_UPPER,
                        liquidityDelta: int256(uint256(liquidity)),
                        salt: positionSalt
                    });

                    (BalanceDelta callerDelta,) = IPoolManager(poolManager).modifyLiquidity(key, liqParams, "");

                    int128 deltaAmount0 = BalanceDeltaLibrary.amount0(callerDelta);
                    int128 deltaAmount1 = BalanceDeltaLibrary.amount1(callerDelta);

                    uint256 actualAmount0 = 0;
                    uint256 actualAmount1 = 0;

                    if (deltaAmount0 < 0) {
                        actualAmount0 = uint256(-int256(deltaAmount0));
                        address token0 = Currency.unwrap(key.currency0);
                        IPoolManager(poolManager).sync(key.currency0);
                        IERC20(token0).safeTransfer(poolManager, actualAmount0);
                        IPoolManager(poolManager).settle();
                    }

                    if (deltaAmount1 < 0) {
                        actualAmount1 = uint256(-int256(deltaAmount1));
                        address token1 = Currency.unwrap(key.currency1);
                        IPoolManager(poolManager).sync(key.currency1);
                        IERC20(token1).safeTransfer(poolManager, actualAmount1);
                        IPoolManager(poolManager).settle();
                    }

                    uint256 wethUsed = wethIsCurrency1 ? actualAmount1 : actualAmount0;
                    uint256 tokensUsed = wethIsCurrency1 ? actualAmount0 : actualAmount1;

                    totalLiquidityAdded += wethUsed;
                    totalLiquidityEvents++;

                    emit LiquidityAdded(poolId, wethUsed, tokensUsed, liquidity);

                    uint256 residualWeth = wethForLiquidity > wethUsed ? wethForLiquidity - wethUsed : 0;
                    uint256 residualTokensAmt = tokensReceived > tokensUsed ? tokensReceived - tokensUsed : 0;

                    if (residualTokensAmt > 0) {
                        ERC20Burnable(config.tokenAddress).burn(residualTokensAmt);
                    }

                    if (residualWeth > 0) {
                        config.accumulated += residualWeth;
                    }

                    if (residualTokensAmt > 0 || residualWeth > 0) {
                        emit ResidualsBurned(poolId, residualTokensAmt, residualWeth);
                    }
                }
            }
        }

        _liquidityInProgress = false;
    }

    function executeLiquidityAdd(PoolKey calldata key) external {
        require(!_liquidityInProgress, "Liquidity add in progress");
        _liquidityInProgress = true;

        bytes32 poolId = _getPoolId(key);
        LiquidityConfig storage config = liquidityConfigs[poolId];

        require(config.enabled, "Not enabled");
        require(config.accumulated >= config.threshold, "Threshold not reached");

        uint256 wethBalance = IERC20(weth).balanceOf(address(this));
        require(wethBalance > 0, "No WETH for liquidity");

        uint256 totalAmount = wethBalance < config.accumulated ? wethBalance : config.accumulated;
        config.accumulated = config.accumulated > totalAmount ? config.accumulated - totalAmount : 0;

        uint256 platformFee = (totalAmount * config.platformFeeBps) / FEE_DENOMINATOR;
        uint256 liquidityBudget = totalAmount - platformFee;

        if (platformFee > 0 && platformFeeCollector != address(0)) {
            IWETH(weth).withdraw(platformFee);
            (bool success, ) = payable(platformFeeCollector).call{value: platformFee}("");
            require(success, "Platform fee transfer failed");
            totalPlatformFees += platformFee;
            emit PlatformFeeSent(poolId, platformFee, platformFeeCollector);
        }

        if (liquidityBudget > 0) {
            IERC20(weth).approve(poolManager, liquidityBudget);
            bytes memory data = abi.encode(key, liquidityBudget, config.tokenAddress, poolId);
            IPoolManager(poolManager).unlock(data);
        }

        _liquidityInProgress = false;
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == poolManager, "Not PoolManager");

        (PoolKey memory key, uint256 liquidityBudget, address tokenAddress, bytes32 poolId) =
            abi.decode(data, (PoolKey, uint256, address, bytes32));

        uint256 wethForTokenBuy = liquidityBudget / 2;
        uint256 wethForLiquidity = liquidityBudget - wethForTokenBuy;

        address currency1Addr = Currency.unwrap(key.currency1);
        bool wethIsCurrency1 = currency1Addr == weth;

        bool zeroForOne = !wethIsCurrency1;

        SwapParams memory swapParams = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(wethForTokenBuy),
            sqrtPriceLimitX96: zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970341
        });

        BalanceDelta swapDelta = IPoolManager(poolManager).swap(key, swapParams, "");

        int128 swapAmount0 = int128(int256(BalanceDelta.unwrap(swapDelta)) >> 128);
        int128 swapAmount1 = int128(int256(BalanceDelta.unwrap(swapDelta)));

        if (swapAmount0 < 0) {
            uint256 amount0Owed = uint256(uint128(-swapAmount0));
            address token0 = Currency.unwrap(key.currency0);
            IPoolManager(poolManager).sync(key.currency0);
            IERC20(token0).safeTransfer(poolManager, amount0Owed);
            IPoolManager(poolManager).settle();
        }

        if (swapAmount1 < 0) {
            uint256 amount1Owed = uint256(uint128(-swapAmount1));
            address token1 = Currency.unwrap(key.currency1);
            IPoolManager(poolManager).sync(key.currency1);
            IERC20(token1).safeTransfer(poolManager, amount1Owed);
            IPoolManager(poolManager).settle();
        }

        uint256 amount0Taken = 0;
        if (swapAmount0 > 0) {
            amount0Taken = uint256(uint128(swapAmount0));
            IPoolManager(poolManager).take(key.currency0, address(this), amount0Taken);
        }

        uint256 amount1Taken = 0;
        if (swapAmount1 > 0) {
            amount1Taken = uint256(uint128(swapAmount1));
            IPoolManager(poolManager).take(key.currency1, address(this), amount1Taken);
        }

        uint256 tokensReceived = wethIsCurrency1 ? amount0Taken : amount1Taken;

        if (wethForLiquidity > 0 && tokensReceived > 0) {
            uint160 sqrtPriceAX96 = LiquidityMath.getSqrtRatioAtTick(FULL_RANGE_LOWER);
            uint160 sqrtPriceBX96 = LiquidityMath.getSqrtRatioAtTick(FULL_RANGE_UPPER);

            uint256 amount0Desired;
            uint256 amount1Desired;
            if (wethIsCurrency1) {
                amount0Desired = tokensReceived;
                amount1Desired = wethForLiquidity;
            } else {
                amount0Desired = wethForLiquidity;
                amount1Desired = tokensReceived;
            }

            uint128 liquidity0 = LiquidityMath.getLiquidityForAmount0(sqrtPriceAX96, sqrtPriceBX96, amount0Desired);
            uint128 liquidity1 = LiquidityMath.getLiquidityForAmount1(sqrtPriceAX96, sqrtPriceBX96, amount1Desired);
            uint128 liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;

            if (liquidity > 0) {
                bytes32 positionSalt = keccak256(abi.encodePacked(poolId, "LiquidityGenHook"));

                ModifyLiquidityParams memory liqParams = ModifyLiquidityParams({
                    tickLower: FULL_RANGE_LOWER,
                    tickUpper: FULL_RANGE_UPPER,
                    liquidityDelta: int256(uint256(liquidity)),
                    salt: positionSalt
                });

                (BalanceDelta callerDelta,) = IPoolManager(poolManager).modifyLiquidity(key, liqParams, "");

                int128 deltaAmount0 = BalanceDeltaLibrary.amount0(callerDelta);
                int128 deltaAmount1 = BalanceDeltaLibrary.amount1(callerDelta);

                uint256 actualAmount0 = 0;
                uint256 actualAmount1 = 0;

                if (deltaAmount0 < 0) {
                    actualAmount0 = uint256(-int256(deltaAmount0));
                    address token0 = Currency.unwrap(key.currency0);
                    IPoolManager(poolManager).sync(key.currency0);
                    IERC20(token0).safeTransfer(poolManager, actualAmount0);
                    IPoolManager(poolManager).settle();
                }

                if (deltaAmount1 < 0) {
                    actualAmount1 = uint256(-int256(deltaAmount1));
                    address token1 = Currency.unwrap(key.currency1);
                    IPoolManager(poolManager).sync(key.currency1);
                    IERC20(token1).safeTransfer(poolManager, actualAmount1);
                    IPoolManager(poolManager).settle();
                }

                uint256 wethUsed = wethIsCurrency1 ? actualAmount1 : actualAmount0;
                uint256 tokensUsed = wethIsCurrency1 ? actualAmount0 : actualAmount1;

                totalLiquidityAdded += wethUsed;
                totalLiquidityEvents++;

                emit LiquidityAdded(poolId, wethUsed, tokensUsed, liquidity);

                uint256 residualWeth = wethForLiquidity > wethUsed ? wethForLiquidity - wethUsed : 0;
                uint256 residualTokensAmt = tokensReceived > tokensUsed ? tokensReceived - tokensUsed : 0;

                if (residualTokensAmt > 0) {
                    ERC20Burnable(tokenAddress).burn(residualTokensAmt);
                }

                if (residualWeth > 0) {
                    liquidityConfigs[poolId].accumulated += residualWeth;
                }

                if (residualTokensAmt > 0 || residualWeth > 0) {
                    emit ResidualsBurned(poolId, residualTokensAmt, residualWeth);
                }
            }
        }

        return "";
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function _getPoolId(PoolKey calldata key) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            Currency.unwrap(key.currency0),
            Currency.unwrap(key.currency1),
            key.fee,
            key.tickSpacing,
            address(key.hooks)
        ));
    }

    function getAccumulated(bytes32 poolId) external view returns (uint256) {
        return liquidityConfigs[poolId].accumulated;
    }

    function isThresholdReached(bytes32 poolId) external view returns (bool) {
        return liquidityConfigs[poolId].accumulated >= liquidityConfigs[poolId].threshold;
    }

    function getWethBalance() external view returns (uint256) {
        return IERC20(weth).balanceOf(address(this));
    }

    function getLiquidityConfig(bytes32 poolId) external view returns (LiquidityConfig memory) {
        return liquidityConfigs[poolId];
    }

    receive() external payable {}
}

library Hooks {
    struct Permissions {
        bool beforeInitialize;
        bool afterInitialize;
        bool beforeAddLiquidity;
        bool afterAddLiquidity;
        bool beforeRemoveLiquidity;
        bool afterRemoveLiquidity;
        bool beforeSwap;
        bool afterSwap;
        bool beforeDonate;
        bool afterDonate;
        bool beforeSwapReturnDelta;
        bool afterSwapReturnDelta;
        bool afterAddLiquidityReturnDelta;
        bool afterRemoveLiquidityReturnDelta;
    }
}
