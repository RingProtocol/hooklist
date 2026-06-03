// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ICurrency.sol";
import "./IHooks.sol";

// BalanceDelta is a packed int256 where:
// - Upper 128 bits = amount0 (int128)
// - Lower 128 bits = amount1 (int128)
type BalanceDelta is int256;

/// @notice Library for getting amount0/amount1 from BalanceDelta
library BalanceDeltaLibrary {
    function amount0(BalanceDelta balanceDelta) internal pure returns (int128 _amount0) {
        assembly ("memory-safe") {
            _amount0 := sar(128, balanceDelta)
        }
    }

    function amount1(BalanceDelta balanceDelta) internal pure returns (int128 _amount1) {
        assembly ("memory-safe") {
            _amount1 := signextend(15, balanceDelta)
        }
    }
}

/// @notice PoolKey identifies a V4 pool
struct PoolKey {
    Currency currency0;
    Currency currency1;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
}

/// @notice Parameters for modifyLiquidity
struct ModifyLiquidityParams {
    int24 tickLower;
    int24 tickUpper;
    int256 liquidityDelta;
    bytes32 salt;
}

/// @notice Interface for Uniswap V4 PoolManager
interface IPoolManager {
    /// @notice Initialize the state for a given pool
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);

    /// @notice Modify the liquidity for the given pool
    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta callerDelta, BalanceDelta feesAccrued);

    /// @notice All interactions on the contract that account deltas require unlocking
    function unlock(bytes calldata data) external returns (bytes memory);

    /// @notice Sync the currency to its current balance in the PoolManager
    function sync(Currency currency) external;

    /// @notice Settle the currency, paying what is owed
    function settle() external payable returns (uint256 paid);
    
    /// @notice Take currency from the PoolManager
    /// @param currency The currency to take
    /// @param to The address to receive the currency
    /// @param amount The amount to take
    function take(Currency currency, address to, uint256 amount) external;
    
    /// @notice Execute a swap
    /// @param key The pool key
    /// @param params The swap parameters
    /// @param hookData Any data to be passed to hooks
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta swapDelta);
}

