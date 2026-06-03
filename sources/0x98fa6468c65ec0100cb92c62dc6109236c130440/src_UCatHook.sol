// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";

import {IRandomSeedProvider} from "./interfaces/IRandomSeedProvider.sol";
import {IStartableToken} from "./interfaces/IStartableToken.sol";

contract UCatHook is IHooks, IRandomSeedProvider {
    IPoolManager public immutable poolManager;
    address public immutable token;
    uint256 public seed;
    uint256 public swapCount;

    error NotPoolManager();
    error NotImplemented();

    event Randomized(uint256 indexed swapCount, uint256 seed);

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(IPoolManager _pm, address _token) {
        poolManager = _pm;
        token = _token;
        seed = uint256(keccak256(abi.encode(block.timestamp, _token)));
    }

    // ----- active hooks -----

    function afterAddLiquidity(
        address, PoolKey calldata key, ModifyLiquidityParams calldata,
        BalanceDelta, BalanceDelta, bytes calldata
    ) external onlyPoolManager returns (bytes4, BalanceDelta) {
        if (_involves(key) && !IStartableToken(token).started()) {
            IStartableToken(token).start();
        }
        return (this.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function afterSwap(
        address, PoolKey calldata key, SwapParams calldata,
        BalanceDelta, bytes calldata
    ) external onlyPoolManager returns (bytes4, int128) {
        if (_involves(key)) _randomize();
        return (this.afterSwap.selector, 0);
    }

    // ----- inactive hooks (PoolManager won't call these because address bits are off) -----

    function beforeInitialize(address, PoolKey calldata, uint160) external pure returns (bytes4) { revert NotImplemented(); }
    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) { revert NotImplemented(); }
    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata) external pure returns (bytes4) { revert NotImplemented(); }
    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata) external pure returns (bytes4) { revert NotImplemented(); }
    function afterRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata) external pure returns (bytes4, BalanceDelta) { revert NotImplemented(); }
    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata) external pure returns (bytes4, BeforeSwapDelta, uint24) { revert NotImplemented(); }
    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) { revert NotImplemented(); }
    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) { revert NotImplemented(); }

    // ----- internals -----

    function _randomize() internal {
        unchecked { swapCount++; }
        seed = uint256(keccak256(abi.encode(
            seed, swapCount, block.timestamp, block.prevrandao, block.number
        )));
        emit Randomized(swapCount, seed);
    }

    function _involves(PoolKey calldata key) internal view returns (bool) {
        return Currency.unwrap(key.currency0) == token || Currency.unwrap(key.currency1) == token;
    }
}
