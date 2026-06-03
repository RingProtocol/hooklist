// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "./PoolKey.sol";
import {BalanceDelta} from "./BalanceDelta.sol";
import {BeforeSwapDelta} from "./BeforeSwapDelta.sol";
import {IPoolManager} from "./IPoolManager.sol";

/// @notice V4 decides whether to invoke specific hooks by inspecting the least significant bits
/// of the address that the hooks contract is deployed to.
/// @dev Should only be callable by the v4 PoolManager.
interface IHooks {
  /// @notice The hook called before the state of a pool is initialized
  function beforeInitialize(
    address sender,
    PoolKey calldata key,
    uint160 sqrtPriceX96
  ) external returns (bytes4);

  /// @notice The hook called after the state of a pool is initialized
  function afterInitialize(
    address sender,
    PoolKey calldata key,
    uint160 sqrtPriceX96,
    int24 tick
  ) external returns (bytes4);

  /// @notice The hook called before a swap
  function beforeSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    bytes calldata hookData
  ) external returns (bytes4, BeforeSwapDelta, uint24);

  /// @notice The hook called after a swap
  function afterSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
  ) external returns (bytes4, int128);
}
