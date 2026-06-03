// SPDX-License-Identifier: MIT
// Qian Exchange - https://qian.ag
pragma solidity ^0.8.24;

import "./IPoolManager.sol";

/// @notice Swap parameters for hook callbacks
struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

/// @notice Uniswap V4 Hooks interface
/// Hooks can implement various callbacks to customize pool behavior
interface IHooks {
    /// @notice Called before a pool is initialized
    function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96) external returns (bytes4);
    
    /// @notice Called after a pool is initialized
    function afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick) external returns (bytes4);
    
    /// @notice Called before a swap
    function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData) external returns (bytes4, BeforeSwapDelta, uint24);
    
    /// @notice Called after a swap
    function afterSwap(address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata hookData) external returns (bytes4, int128);
    
    /// @notice Called before liquidity is added
    function beforeAddLiquidity(address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData) external returns (bytes4);
    
    /// @notice Called after liquidity is added
    function afterAddLiquidity(address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, BalanceDelta delta, BalanceDelta feesAccrued, bytes calldata hookData) external returns (bytes4, BalanceDelta);
    
    /// @notice Called before liquidity is removed
    function beforeRemoveLiquidity(address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData) external returns (bytes4);
    
    /// @notice Called after liquidity is removed
    function afterRemoveLiquidity(address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, BalanceDelta delta, BalanceDelta feesAccrued, bytes calldata hookData) external returns (bytes4, BalanceDelta);
    
    /// @notice Called before a donate
    function beforeDonate(address sender, PoolKey calldata key, uint256 amount0, uint256 amount1, bytes calldata hookData) external returns (bytes4);
    
    /// @notice Called after a donate
    function afterDonate(address sender, PoolKey calldata key, uint256 amount0, uint256 amount1, bytes calldata hookData) external returns (bytes4);
}

/// @notice Before swap delta type - encodes (specifiedDelta, unspecifiedDelta)
type BeforeSwapDelta is int256;

