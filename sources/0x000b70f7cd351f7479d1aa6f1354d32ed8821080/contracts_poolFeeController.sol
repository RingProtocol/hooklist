// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {PositionInfo} from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";

import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";


interface IUniswapV2Pair {
    function getReserves() external view returns (uint112, uint112, uint32);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
}

interface IERC20 {
	function totalSupply() external view returns (uint256);

	function balanceOf(address account) external view returns (uint256);

	function transfer(address recipient, uint256 amount) external returns (bool);

	function decimals() external view returns (uint8);

	function allowance(
		address owner,
		address spender
	) external view returns (uint256);

	function approve(address spender, uint256 amount) external returns (bool);

	function transferFrom(
		address sender,
		address recipient,
		uint256 amount
	) external returns (bool);

	event Transfer(address indexed from, address indexed to, uint256 value);
	event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

abstract contract Context {
	function _msgSender() internal view virtual returns (address) {
		return msg.sender;
	}

	function _msgData() internal view virtual returns (bytes calldata) {
		return msg.data;
	}
}

abstract contract Ownable is Context {
	address private _owner;

	event OwnershipTransferred(
		address indexed previousOwner,
		address indexed newOwner
	);

	constructor() {
		_transferOwnership(_msgSender());
	}

	modifier onlyOwner() {
		_checkOwner();
		_;
	}

	function owner() public view virtual returns (address) {
		return _owner;
	}

	function _checkOwner() internal view virtual {
		require(owner() == _msgSender(), "Ownable: caller is not the owner");
	}

	function renounceOwnership() public virtual onlyOwner {
		_transferOwnership(address(0));
	}

	function transferOwnership(address newOwner) public virtual onlyOwner {
		require(newOwner != address(0), "Ownable: new owner is the zero address");
		_transferOwnership(newOwner);
	}

	function _transferOwnership(address newOwner) internal virtual {
		address oldOwner = _owner;
		_owner = newOwner;
		emit OwnershipTransferred(oldOwner, newOwner);
	}
}


contract PoolTraderHook is Ownable, BaseHook {

    // Constants and contracts for interacting with Uniswap V2
	address internal immutable WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IUniswapV2Factory constant v2Factory = IUniswapV2Factory(address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f));

    // Total: 256 bits
    struct FeeCurve {
        // Numerator
        int40 A;  // X^2
        int40 B;  // X
        int40 C;  // 1

        // Denominator
        int40 I;  // X^2
        int40 J;  // X
        int40 K;  // 1

        // Added after rational equation
        // This number is converted to int24 and multiplied by 10 before addition
        // We can't use int24 here because our struct would take up another storage slot
        int16 offset;
    }

    // Total: 256 bits
    struct FilterConfig {
        uint64 alpha;  // Filter update speed to TWAP
        uint64 beta;   // Filter update speed to latest price

        // These are used to scale the filter weights.
        // This can be used to limit the extent to which a filter can
        // be updated from a certain variable.
        // The scale is 1e-4 %, so for 100% put 1000000
        uint64 twapPriceWeightMultiplier;
        uint64 latestPriceWeightMultiplier;
    }

    // Total: 256 bits
    struct GlobalConfig {
        address feeRecipient;

        // Set this to zero to disable
        uint72 automaticFeeDistributionThreshold;

        // Developer fee rate, in 1e-4 % increments, to match Uniswap
        // This fee applies to the pool's fees, so if the pool charges
        // a 1% fee for a trade and the developer fee is 1%, then the
        // developer receives 0.01% of the transaction.
        // Code below requires that this is no greater than 25%.
        uint24 developerFeeRate;
    }

    // Total: 512 bits
    struct TokenStateInformation {
        // First storage slot
        uint192 filteredPriceX96;
        uint64 lastTimestamp;

        // Second storage slot
        uint256 lastCumulativePrice;
    }

    // Total: 256 bits
    struct TokenPoolInformation {
        IUniswapV2Pair pool;   // 160 bits
        uint64 reserved;
        uint32 flags;
    }

    // Configuration per token
    mapping (address => FeeCurve) public feeCurves;
    mapping (address => FilterConfig) public filters;

    // Global configuration
    GlobalConfig public config;

    // Stored state per token
    mapping(address => TokenStateInformation) public tokenStates;
    mapping(address => TokenPoolInformation) public tokenPoolInfos;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) { }

    //
    // DYNAMIC FEE COMPUTATION
    //

    function getFee(address token, uint256 spotPriceX96, uint256 filterPrice) public view returns (uint24 fee) {

        // Compute the absolute difference in price, in units of 1e-4 percent
        // This unit is designed to be consistent with Uniswap's units for fee percentages.
        int256 ratio = ((int256(spotPriceX96) - int256(filterPrice)) * 10_000) / int256(filterPrice);
        if (ratio < 0)
            ratio = -ratio;

        // Run our reprogrammable equation for computing the fee
        // This code is designed to use only one SLOAD.
        FeeCurve memory curve = feeCurves[token];
        int256 numerator = ratio * ratio * curve.A + ratio * curve.B + int256(curve.C) * 10_000;
        int256 denominator = ratio * ratio * curve.I + ratio * curve.J + int256(curve.K) * 10_000;
        int256 feeTmp = (numerator * 10_000) / denominator;

        // Constrain to a reasonable range and return
        if (feeTmp > 900_000)
            return 900_000;
        else if (feeTmp < 1_000)
            return 1_000;
        else
            return uint24(uint256(feeTmp));
    }

    function getFee(address token) public view returns (uint24 fee) {
        TokenPoolInformation memory poolInfo = tokenPoolInfos[token];
        TokenStateInformation memory state = tokenStates[token];
        (uint112 reserve0, uint112 reserve1,) = poolInfo.pool.getReserves();
        uint256 spotPriceX96 = (poolInfo.flags & 1) == 0 ? (uint256(reserve1) << 96) / reserve0 : (uint256(reserve0) << 96) / reserve1;
        return getFee(token, spotPriceX96, state.filteredPriceX96);
    }

    //
    // UNISWAP V4 HOOK IMPLEMENTATION
    //

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _afterInitialize(address, PoolKey calldata key, uint160, int24) internal override returns (bytes4) {
        require(Currency.unwrap(key.currency0) == address(0), "Can only create pools that swap against ETH with this hook.");

        address token = Currency.unwrap(key.currency1);
        address v2PairAddress = v2Factory.getPair(WETH, token);

        require(v2PairAddress != address(0), "No Uniswap V2 pair found :/");

        TokenPoolInformation memory poolInfo = TokenPoolInformation(IUniswapV2Pair(v2PairAddress), 0, token < WETH ? 1 : 0);

        // Get V2 pool price
        (uint112 reserve0, uint112 reserve1,) = poolInfo.pool.getReserves();
        uint256 spotPriceX96 = poolInfo.flags & 1 == 0 ? (uint256(reserve1) << 96) / reserve0 : (uint256(reserve0) << 96) / reserve1;

        // Get cumulative price data from the pool
        uint256 priceCumulative = poolInfo.flags & 1 == 0 ? poolInfo.pool.price0CumulativeLast() : poolInfo.pool.price1CumulativeLast();

        // Initialize data about this token
        feeCurves[token] = FeeCurve(810, 679, 667, 33, -100, 2084, 0);
        filters[token] = FilterConfig(18000, 10000, 1000000, 1000000);
        tokenStates[token] = TokenStateInformation(uint192(spotPriceX96), uint64(block.timestamp), priceCumulative);
        tokenPoolInfos[token] = poolInfo;
        
        return BaseHook.afterInitialize.selector;
    }

    event FeeControlledSwap(uint24 fee, uint24 developerFeeThisTime, uint256 totalInputTokens);
    event FeesCollected(address recipient);

    function processDeveloperFee(PoolKey calldata key, IPoolManager.SwapParams calldata swapParams, address token, uint24 swapFee) internal returns (uint256 developerFeesCollected, uint24 poolFee) {
        GlobalConfig memory _config = config; 

        // Adjust our fee so the developer can get some
        uint24 developerFeeThisTime = uint24((uint48(_config.developerFeeRate) * uint48(swapFee)) / 1e6);
        poolFee = swapFee - developerFeeThisTime;

        // Compute developer fees in absolute units and handle the transfer
        uint256 specifiedTokens = uint256(swapParams.amountSpecified < 0 ? -swapParams.amountSpecified : swapParams.amountSpecified);
        developerFeesCollected = (specifiedTokens * developerFeeThisTime) / 1e6;

        // taking a developer fee on the specified token
        if (swapParams.zeroForOne != (swapParams.amountSpecified < 0)) {
            poolManager.mint(address(this), key.currency1.toId(), developerFeesCollected);
        } else {
            poolManager.mint(address(this), key.currency0.toId(), developerFeesCollected);
        }

        // Automatic fee collection logic
        if (_config.automaticFeeDistributionThreshold > 0) {
            if (_config.automaticFeeDistributionThreshold < address(this).balance) {

                // Send our eth first
                // Even if our balance is empty, this function is called so that if the
                // fee recipient is a smart contract, the logic for that contract will
                // execute even if there is no eth to send (just tokens)
                // We use eth.send because we need the swap to continue regardless
                // of the success of this payment
                // If this fails the owner can figure out how fee dispursement should be
                // corrected, if necessary.
                bool success = payable(_config.feeRecipient).send(address(this).balance);

                // Only send tokens if our eth payment was successful
                // This helps protect funds from mistakes or incorrect smart contracts
                if (success) {
                    // For each specified token, send our whole balance
                    uint256 balance = IERC20(token).balanceOf(address(this));
                    IERC20(token).transfer(_config.feeRecipient, balance);

                    emit FeesCollected(_config.feeRecipient);
                }
            }
        }

        emit FeeControlledSwap(swapFee, developerFeeThisTime, specifiedTokens);
    }

    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata swapParams, bytes calldata) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        address token = Currency.unwrap(key.currency1);

        // Get configuration data loaded in minimum SLOADs
        TokenPoolInformation memory poolInfo = tokenPoolInfos[token];

        // Compute the desired fee rate for this swap based on market conditions
        (uint112 reserve0, uint112 reserve1,) = poolInfo.pool.getReserves();
        uint256 spotPriceX96 = (uint256(reserve1) << 96) / reserve0;
        uint24 swapFee = getFee(token, spotPriceX96, updateFilteredPrice(poolInfo, token, spotPriceX96));

        (uint256 developerFeesCollected, uint24 poolFee) = processDeveloperFee(key, swapParams, token, swapFee);

        return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(int128(int256(developerFeesCollected)), 0), poolFee | 0x400000);
    }

    //
    // OWNER ONLY METHODS FOR CONFIGURATION
    //

    function configureFilter(address token, uint64 alpha, uint64 beta, uint64 ratioAlpha, uint64 ratioBeta) external onlyOwner {
        // The ratios must never exceed 1000000.
        require(ratioAlpha <= 1000000 && ratioBeta <= 1000000, "Ratios cannot exceed 100% (1000000 units)");
        filters[token] = FilterConfig(alpha, beta, ratioAlpha, ratioBeta);
    }

    function configureFeeCurve(address token, int40 A, int40 B, int40 C, int40 I, int40 J, int40 K, int16 offset) external onlyOwner {
        feeCurves[token] = FeeCurve(A, B, C, I, J, K, offset);
    }

    function setGlobalConfig(address feeRecipient, uint72 automaticFeeDistributeThreshold, uint24 developerFeeRate) external onlyOwner {
        // Protect LPs from too high of developer fees
        require(developerFeeRate < 250_000, "Fee rate too high, maximum is 25% or 250000 units");

        config = GlobalConfig(feeRecipient, automaticFeeDistributeThreshold, developerFeeRate);
    }

    //
    // MANUAL FEE COLLECTION
    //

    function collectFees(address[] calldata tokens) public {
        address recipient = config.feeRecipient;

        // This is commented out because our fees are ALWAYS sent to the
        // correct recipient, so if someone wants to pay for the gas to
        // collect the fees, they sure can.  Makes integration with
        // smart contracts easier in the future too, and allows
        // this contract to call this function without extra logic.
        //require(_msgSender() == recipient, "Not fee recipient");

        // For each specified token, send our whole balance
        for (uint16 i = 0; i < tokens.length;) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            IERC20(tokens[i]).transfer(recipient, balance);

            unchecked { i++; }
        }

        // Send our eth too
        // Even if our balance is empty, this function is called so that if the
        // fee recipient is a smart contract, the logic for that contract will
        // execute even if there is no eth to send (just tokens)
        payable(recipient).transfer(address(this).balance);

        emit FeesCollected(recipient);
    }

    //
    // PRICE FILTER
    //

    function updateFilter(address token) external returns (uint256 newFilteredPrice) {
        TokenPoolInformation memory poolInfo = tokenPoolInfos[token];
        (uint112 reserve0, uint112 reserve1,) = poolInfo.pool.getReserves();
        uint256 spotPriceX96 = poolInfo.flags & 1 == 0 ? (uint256(reserve1) << 96) / reserve0 : (uint256(reserve0) << 96) / reserve1;
        return updateFilteredPrice(poolInfo, token, spotPriceX96);
    }

    function updateFilteredPrice(TokenPoolInformation memory poolInfo, address token, uint256 spotPriceX96) public returns (uint256 newFilteredPrice) {
        FilterConfig memory filter = filters[token];
        TokenStateInformation memory state = tokenStates[token];

        uint256 deltaT;
        unchecked {
            deltaT = block.timestamp - uint256(state.lastTimestamp);
        }
        if (deltaT < 15 minutes)
            return state.filteredPriceX96;

        uint256 priceCumulative = poolInfo.flags & 1 == 0 ? poolInfo.pool.price0CumulativeLast() : poolInfo.pool.price1CumulativeLast();

        // I've checked this math, this should never overflow.
        // Worst case impact is that the fees go up to 25% or down to 0.1%
        // This assumes twapPriceWeightMultiplier and latestPriceWeightMultiplier never exceed 1000000,
        // but this is checked when these values are set by the owner.
        unchecked {
            uint256 averagePriceX96 = ((priceCumulative - state.lastCumulativePrice) / deltaT) >> 16;

            // Compute smoothing factor K = Δt / (Δt + α)
            //    This increases with the staleness of the data
            uint256 K = (deltaT * 1e18) / (deltaT + filter.alpha);
            K = (K * filter.twapPriceWeightMultiplier) / 1000000;

            // Compute W_avg = Δt / (Δt + β)
            //    This increases with the staleness of the data
            uint256 W_avg = (deltaT * 1e9) / (deltaT + filter.beta);
            W_avg *= W_avg;
            W_avg = (W_avg * filter.latestPriceWeightMultiplier) / 1000000;

            // Filtered price update
            uint256 mixedPrice = (averagePriceX96 * (1e18 - W_avg) + spotPriceX96 * W_avg) / 1e18;
            newFilteredPrice = (uint256(state.filteredPriceX96) * (1e18 - K) + mixedPrice * K) / 1e18;
        }

        // Store updates
        state.filteredPriceX96 = uint192(newFilteredPrice);
        state.lastTimestamp = uint64(block.timestamp);
        state.lastCumulativePrice = priceCumulative;
        tokenStates[token] = state;
    }

    function getFilteredPrice(address token) external view returns (uint256) {
        return tokenStates[token].filteredPriceX96;
    }

    //
    // UTILITIES AND MISCELANIOUS FUNCTIONS
    //

    // Copied from https://github.com/Uniswap/v4-core/blob/main/src/types/BeforeSwapDelta.sol
    // Not sure why the libraries I imported don't compile properly :P
    function toBeforeSwapDelta(int128 deltaSpecified, int128 deltaUnspecified) pure internal returns (BeforeSwapDelta beforeSwapDelta) {
        assembly ("memory-safe") {
            beforeSwapDelta := or(shl(128, deltaSpecified), and(sub(shl(128, 1), 1), deltaUnspecified))
        }
    }
}
