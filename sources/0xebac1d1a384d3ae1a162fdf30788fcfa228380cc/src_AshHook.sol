// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "./interfaces/uniswap-v4/BaseHook.sol";
import {IPoolManager} from "./interfaces/uniswap-v4/IPoolManager.sol";
import {Hooks} from "./interfaces/uniswap-v4/Hooks.sol";
import {PoolKey} from "./interfaces/uniswap-v4/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "./interfaces/uniswap-v4/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "./interfaces/uniswap-v4/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "./interfaces/uniswap-v4/Currency.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IPoolManagerTake {
    function take(Currency currency, address to, uint256 amount) external;
}

interface IAshTokenSwapAuth {
    function enterSwap() external;
    function exitSwap() external;
}

/**
 * @title AshHook
 * @notice Uniswap V4 hook for ASH/ETH pool — captures protocol trading fees.
 *         5% ETH fee on buys and sells. Fees sent to treasury.
 *         [H8] Failed fee transfers accumulate safely; swaps never break.
 *         Permissions: 0xCC (beforeSwap + afterSwap + returnDeltas)
 */
contract AshHook is BaseHook, Ownable {
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    address public immutable ashToken;
    address public treasury;

    uint256 public feeRate = 500; // 5% in basis points
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_FEE_RATE = 1000; // [L2] Max 10%

    bool public hookPaused;

    // [H8] Accumulated fees from failed treasury transfers
    uint256 public accumulatedFees;

    error ExactOutputNotAllowed();
    error WrongPool();

    event FeesCollected(uint256 fee, bool isBuy);
    event FeeTransferFailed(uint256 fee); // [H8]
    event AccumulatedFeesWithdrawn(uint256 amount); // [H8]
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury); // [M9]
    event FeeRateUpdated(uint256 oldRate, uint256 newRate); // [M9]

    constructor(
        IPoolManager _poolManager,
        address _ashToken,
        address _treasury,
        address _owner
    ) BaseHook(_poolManager) Ownable(_owner) {
        require(_ashToken != address(0), "Invalid ash token");
        require(_treasury != address(0), "Invalid treasury");
        ashToken = _ashToken;
        treasury = _treasury;
    }

    // ═══════════════════════════════════════════════════════════════
    //                     HOOK PERMISSIONS
    // ═══════════════════════════════════════════════════════════════

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
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

    // ═══════════════════════════════════════════════════════════════
    //                   NO-OPS
    // ═══════════════════════════════════════════════════════════════

    function beforeInitialize(address, PoolKey calldata, uint160) external pure returns (bytes4) {
        return this.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        return this.afterInitialize.selector;
    }

    function beforeAddLiquidity(
        address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata
    ) external pure returns (bytes4) {
        return this.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, BalanceDelta, bytes calldata
    ) external pure returns (bytes4) {
        return this.afterAddLiquidity.selector;
    }

    function beforeRemoveLiquidity(
        address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata
    ) external pure returns (bytes4) {
        return this.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, BalanceDelta, bytes calldata
    ) external pure returns (bytes4) {
        return this.afterRemoveLiquidity.selector;
    }

    // ═══════════════════════════════════════════════════════════════
    //                   BEFORE SWAP — Buy fee
    // ═══════════════════════════════════════════════════════════════

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        if (Currency.unwrap(key.currency0) != address(0) || Currency.unwrap(key.currency1) != ashToken) {
            revert WrongPool();
        }

        if (params.amountSpecified > 0) revert ExactOutputNotAllowed();

        // Authorize swap via transient storage (anti-sidepool)
        IAshTokenSwapAuth(ashToken).enterSwap();

        if (hookPaused) {
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        bool isBuy = params.zeroForOne;
        if (!isBuy) {
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        uint256 absInput = uint256(-params.amountSpecified);
        uint256 fee = (absInput * feeRate) / BASIS_POINTS;
        if (fee == 0) {
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        IPoolManagerTake(address(poolManager)).take(key.currency0, address(this), fee);

        _sendFee(fee, true);

        return (
            this.beforeSwap.selector,
            toBeforeSwapDelta(int128(uint128(fee)), 0),
            0
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //                   AFTER SWAP — Sell fee
    // ═══════════════════════════════════════════════════════════════

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        // Clear swap authorization (must happen for ALL paths — buy, sell, paused)
        try IAshTokenSwapAuth(ashToken).exitSwap() {} catch {}

        if (hookPaused) return (this.afterSwap.selector, 0);

        bool isSell = !params.zeroForOne;
        if (!isSell) return (this.afterSwap.selector, 0);

        int128 ethOutput = delta.amount0();
        if (ethOutput <= 0) return (this.afterSwap.selector, 0);

        uint256 absOutput = uint256(uint128(ethOutput));
        uint256 fee = (absOutput * feeRate) / BASIS_POINTS;
        if (fee == 0) return (this.afterSwap.selector, 0);

        IPoolManagerTake(address(poolManager)).take(key.currency0, address(this), fee);

        _sendFee(fee, false);

        return (this.afterSwap.selector, int128(uint128(fee)));
    }

    // ═══════════════════════════════════════════════════════════════
    //                   FEE DISTRIBUTION
    // ═══════════════════════════════════════════════════════════════

    /// @notice [H8] Try-catch on fee transfer. If treasury reverts,
    ///         fees accumulate safely and swaps continue.
    function _sendFee(uint256 fee, bool isBuy) internal {
        if (fee == 0) return;

        (bool ok, ) = treasury.call{value: fee, gas: 50000}("");
        if (ok) {
            emit FeesCollected(fee, isBuy);
        } else {
            accumulatedFees += fee;
            emit FeeTransferFailed(fee);
        }
    }

    /// @notice [H8] Withdraw accumulated fees from failed transfers
    function withdrawAccumulatedFees() external onlyOwner {
        uint256 amount = accumulatedFees;
        accumulatedFees = 0;
        (bool ok, ) = owner().call{value: amount}("");
        require(ok, "Transfer failed");
        emit AccumulatedFeesWithdrawn(amount);
    }

    // ═══════════════════════════════════════════════════════════════
    //                        ADMIN
    // ═══════════════════════════════════════════════════════════════

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        emit TreasuryUpdated(treasury, _treasury); // [M9]
        treasury = _treasury;
    }

    function setFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate <= MAX_FEE_RATE, "Max 10%"); // [L2]
        emit FeeRateUpdated(feeRate, _feeRate); // [M9]
        feeRate = _feeRate;
    }

    function setHookPaused(bool _paused) external onlyOwner {
        hookPaused = _paused;
    }

    receive() external payable {}
}
