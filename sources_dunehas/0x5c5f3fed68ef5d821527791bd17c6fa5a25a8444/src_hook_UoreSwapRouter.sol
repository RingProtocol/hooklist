// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

interface IERC20 {
    function transferFrom(address, address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

/// @notice Singleton router for swapping ETH↔UORE through the canonical UoreHook pool.
contract UoreSwapRouter {
    uint160 internal constant MIN_SQRT = 4295128739;
    uint160 internal constant MAX_SQRT = 1461446703485210103287273052203988822378723970342;

    IPoolManager public immutable poolManager;
    PoolKey public canonicalKey;
    address public immutable uoreToken;

    address private _activeUser;

    error UnauthorizedCallback();
    error SlippageExceeded();
    error InvalidSwapDir();

    constructor(IPoolManager pm, PoolKey memory key, address uore_) {
        poolManager = pm;
        canonicalKey = key;
        uoreToken = uore_;
    }

    /// @notice Buy UORE with ETH. Caller must send ethIn as msg.value.
    /// @param minUoreOut Slippage protection — revert if output is below this.
    function buy(uint256 minUoreOut) external payable returns (uint256 uoreOut) {
        require(msg.value > 0, "no ETH sent");
        _activeUser = msg.sender;
        bytes memory result = poolManager.unlock(
            abi.encode(true, int256(msg.value), MIN_SQRT + 1, minUoreOut)
        );
        _activeUser = address(0);
        uoreOut = abi.decode(result, (uint256));
    }

    /// @notice Sell UORE for ETH. Caller must approve `uoreIn` UORE to this contract first.
    /// @param uoreIn Amount of UORE to sell.
    /// @param minEthOut Slippage protection — revert if output is below this.
    function sell(uint256 uoreIn, uint256 minEthOut) external returns (uint256 ethOut) {
        require(uoreIn > 0, "zero in");
        require(
            IERC20(uoreToken).transferFrom(msg.sender, address(this), uoreIn),
            "uore pull fail"
        );
        _activeUser = msg.sender;
        bytes memory result = poolManager.unlock(
            abi.encode(false, int256(uoreIn), MAX_SQRT - 1, minEthOut)
        );
        _activeUser = address(0);
        ethOut = abi.decode(result, (uint256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert UnauthorizedCallback();
        (bool zeroForOne, int256 amountIn, uint160 sqrtLimit, uint256 minOut) =
            abi.decode(data, (bool, int256, uint160, uint256));

        BalanceDelta delta = poolManager.swap(
            canonicalKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -amountIn,
                sqrtPriceLimitX96: sqrtLimit
            }),
            ""
        );

        int128 d0 = delta.amount0();
        int128 d1 = delta.amount1();

        // Settle negatives (we owe)
        if (d0 < 0) {
            uint256 owed = uint256(int256(-d0));
            poolManager.settle{value: owed}();
        }
        if (d1 < 0) {
            uint256 owed = uint256(int256(-d1));
            poolManager.sync(canonicalKey.currency1);
            require(IERC20(uoreToken).transfer(address(poolManager), owed), "uore xfer");
            poolManager.settle();
        }

        // Take positives directly to the user where possible. ETH gets taken to
        // address(this) first then forwarded since payable users may be contracts.
        uint256 outAmount;
        if (zeroForOne) {
            // Buying: positive d1 = UORE we receive
            require(d1 > 0, "no out");
            outAmount = uint256(int256(d1));
            require(outAmount >= minOut, "slippage");
            poolManager.take(canonicalKey.currency1, _activeUser, outAmount);
        } else {
            // Selling: positive d0 = ETH we receive
            require(d0 > 0, "no out");
            outAmount = uint256(int256(d0));
            require(outAmount >= minOut, "slippage");
            poolManager.take(canonicalKey.currency0, address(this), outAmount);
            (bool ok, ) = _activeUser.call{value: outAmount}("");
            require(ok, "eth fwd fail");
        }
        return abi.encode(outAmount);
    }

    receive() external payable {}
}
