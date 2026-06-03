// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary,
    toBeforeSwapDelta
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

interface ISlopBuyAndVoidFeeReceiver {
    function depositBuyAndVoidFees() external payable;
}

/// @title SlopPoolHook
/// @notice Uniswap v4 fee hook for the official ETH/SLOP pool.
/// @dev SLOP remains freely transferable; this hook only affects swaps in pools that opt into it.
contract SlopPoolHook is IHooks {
    using BalanceDeltaLibrary for BalanceDelta;
    using CurrencyLibrary for Currency;

    uint256 public constant TOTAL_BIPS = 10_000;
    uint256 public constant POOL_FEE_BIPS = 200;
    uint256 public constant BUY_AND_VOID_SHARE = 5_000;
    uint256 public constant TEAM_SHARE = 5_000;
    uint24 public constant POOL_LP_FEE = 0;
    int24 public constant POOL_TICK_SPACING = 60;

    IPoolManager public immutable poolManager;
    address public immutable slopToken;
    uint256 public immutable launchStartFeeBips;
    uint256 public immutable launchDecayBlocks;
    ISlopBuyAndVoidFeeReceiver public buyAndVoidFeeReceiver;
    address public teamAddress;
    uint256 public launchBlock;

    error OnlyPoolManager();
    error OnlySlopEthPool();
    error InvalidLaunchFee();
    error ExactOutputNotAllowed();
    error Unauthorized();
    error ZeroAddress();

    event TeamAddressUpdated(address indexed oldTeam, address indexed newTeam);
    event BuyAndVoidFeeReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);
    event SlopPoolFeesCollected(
        uint256 ethFee, uint256 normalFee, uint256 launchFee, uint256 buyAndVoidEth, uint256 teamEth
    );
    event TradingLaunched(uint256 indexed launchBlock);

    constructor(
        IPoolManager poolManager_,
        address slopToken_,
        address buyAndVoidFeeReceiver_,
        address teamAddress_,
        uint256 launchStartFeeBips_,
        uint256 launchDecayBlocks_
    ) {
        if (
            address(poolManager_) == address(0) || slopToken_ == address(0) || buyAndVoidFeeReceiver_ == address(0)
                || teamAddress_ == address(0)
        ) {
            revert ZeroAddress();
        }
        if (launchStartFeeBips_ < POOL_FEE_BIPS || launchStartFeeBips_ > TOTAL_BIPS) revert InvalidLaunchFee();

        poolManager = poolManager_;
        slopToken = slopToken_;
        launchStartFeeBips = launchStartFeeBips_;
        launchDecayBlocks = launchDecayBlocks_;
        buyAndVoidFeeReceiver = ISlopBuyAndVoidFeeReceiver(buyAndVoidFeeReceiver_);
        teamAddress = teamAddress_;
        _validateHookAddress();
    }

    function setTeamAddress(address newTeam) external {
        if (msg.sender != teamAddress) revert Unauthorized();
        if (newTeam == address(0)) revert ZeroAddress();
        address oldTeam = teamAddress;
        teamAddress = newTeam;
        emit TeamAddressUpdated(oldTeam, newTeam);
    }

    function setBuyAndVoidFeeReceiver(address newReceiver) external {
        if (msg.sender != teamAddress) revert Unauthorized();
        if (newReceiver == address(0)) revert ZeroAddress();
        address oldReceiver = address(buyAndVoidFeeReceiver);
        buyAndVoidFeeReceiver = ISlopBuyAndVoidFeeReceiver(newReceiver);
        emit BuyAndVoidFeeReceiverUpdated(oldReceiver, newReceiver);
    }

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
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

    function beforeInitialize(address, PoolKey calldata key, uint160) external view returns (bytes4) {
        _onlyPoolManager();
        _validatePool(key);
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external view returns (bytes4) {
        _onlyPoolManager();
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        view
        returns (bytes4)
    {
        _onlyPoolManager();
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external view returns (bytes4, BalanceDelta) {
        _onlyPoolManager();
        return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        view
        returns (bytes4)
    {
        _onlyPoolManager();
        return IHooks.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external view returns (bytes4, BalanceDelta) {
        _onlyPoolManager();
        return (IHooks.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        _onlyPoolManager();
        _validatePool(key);
        if (params.amountSpecified > 0) revert ExactOutputNotAllowed();

        if (params.zeroForOne) {
            if (launchBlock == 0) {
                launchBlock = block.number;
                emit TradingLaunched(block.number);
            }
            uint256 inputAmount = uint256(-params.amountSpecified);
            uint256 ethFee = (inputAmount * currentFeeBips()) / TOTAL_BIPS;
            if (ethFee != 0) {
                uint256 normalFee = (inputAmount * POOL_FEE_BIPS) / TOTAL_BIPS;
                assembly {
                    tstore(0, ethFee)
                    tstore(1, normalFee)
                }
                return (IHooks.beforeSwap.selector, toBeforeSwapDelta(int128(uint128(ethFee)), 0), 0);
            }
        }

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata)
        external
        returns (bytes4, int128)
    {
        _onlyPoolManager();
        _validatePool(key);

        if (params.zeroForOne) {
            uint256 ethFee;
            uint256 normalFee;
            assembly {
                ethFee := tload(0)
                normalFee := tload(1)
                tstore(0, 0)
                tstore(1, 0)
            }

            if (ethFee != 0) {
                poolManager.take(key.currency0, address(this), ethFee);
                _distributeEthFee(ethFee, normalFee);
            }
            return (IHooks.afterSwap.selector, 0);
        }

        int128 ethOutput = delta.amount0();
        if (ethOutput < 0) ethOutput = -ethOutput;

        uint256 sellFee = (uint256(uint128(ethOutput)) * POOL_FEE_BIPS) / TOTAL_BIPS;
        if (sellFee != 0) {
            poolManager.take(key.currency0, address(this), sellFee);
            _distributeEthFee(sellFee, sellFee);
        }

        return (IHooks.afterSwap.selector, int128(uint128(sellFee)));
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external view returns (bytes4) {
        _onlyPoolManager();
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external view returns (bytes4) {
        _onlyPoolManager();
        return IHooks.afterDonate.selector;
    }

    function currentFeeBips() public view returns (uint256 feeBips) {
        uint256 startFee = launchStartFeeBips;
        uint256 startBlock = launchBlock;
        if (startBlock == 0) return startFee;
        uint256 decay = launchDecayBlocks;
        if (decay == 0 || block.number >= startBlock + decay) return POOL_FEE_BIPS;

        uint256 elapsed = block.number - startBlock;
        uint256 launchFeeDrop = ((startFee - POOL_FEE_BIPS) * elapsed) / decay;
        return startFee - launchFeeDrop;
    }

    function _distributeEthFee(uint256 ethFee, uint256 normalFee) internal {
        if (normalFee > ethFee) normalFee = ethFee;
        uint256 launchFee = ethFee - normalFee;
        uint256 buyAndVoidEth = launchFee + ((normalFee * BUY_AND_VOID_SHARE) / TOTAL_BIPS);
        uint256 teamEth = ethFee - buyAndVoidEth;

        if (buyAndVoidEth != 0) {
            buyAndVoidFeeReceiver.depositBuyAndVoidFees{value: buyAndVoidEth}();
        }
        if (teamEth != 0) {
            SafeTransferLib.forceSafeTransferETH(teamAddress, teamEth);
        }

        emit SlopPoolFeesCollected(ethFee, normalFee, launchFee, buyAndVoidEth, teamEth);
    }

    function _validatePool(PoolKey calldata key) internal view {
        if (!key.currency0.isAddressZero()) revert OnlySlopEthPool();
        if (Currency.unwrap(key.currency1) != slopToken) revert OnlySlopEthPool();
        if (key.fee != POOL_LP_FEE || key.tickSpacing != POOL_TICK_SPACING) revert OnlySlopEthPool();
    }

    function _validateHookAddress() internal view virtual {
        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
    }

    function _onlyPoolManager() internal view {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
    }

    receive() external payable {}
}
