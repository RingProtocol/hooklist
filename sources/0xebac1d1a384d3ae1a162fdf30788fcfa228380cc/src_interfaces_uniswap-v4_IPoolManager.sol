// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "./PoolKey.sol";
import {BalanceDelta} from "./BalanceDelta.sol";
import {Currency} from "./Currency.sol";

interface IPoolManager {
  struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
  }

  struct ModifyLiquidityParams {
    int24 tickLower;
    int24 tickUpper;
    int256 liquidityDelta;
    bytes32 salt;
  }

  function swap(
    PoolKey memory key,
    SwapParams memory params,
    bytes calldata hookData
  ) external returns (BalanceDelta);

  function initialize(
    PoolKey memory key,
    uint160 sqrtPriceX96,
    bytes calldata hookData
  ) external returns (int24);

  function unlock(bytes calldata data) external payable returns (bytes memory);

  function modifyLiquidity(
    PoolKey memory key,
    ModifyLiquidityParams memory params,
    bytes calldata hookData
  ) external returns (BalanceDelta, BalanceDelta);

  function settle(Currency currency) external payable returns (uint256);

  function take(Currency currency, address to, uint256 amount) external;
}
