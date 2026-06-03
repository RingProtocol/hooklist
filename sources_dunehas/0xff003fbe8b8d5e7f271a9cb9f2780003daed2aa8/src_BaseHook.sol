// flood.markets
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";

/// Minimal V4 hook abstract. v4-periphery 1.0.4 removed its own BaseHook,
/// so we vend a tiny in-tree replacement. Validates msg.sender == poolManager
/// for every callback, validates flag bits at deploy, exposes empty default
/// implementations that subclasses override via _beforeSwap, _beforeInitialize, etc.
abstract contract BaseHook is IHooks {
    error NotPoolManager();
    error HookNotImplemented();
    error InvalidHookFlags();

    IPoolManager public immutable poolManager;

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
    }

    function getHookPermissions() public pure virtual returns (Hooks.Permissions memory);

    // ---- IHooks dispatch ----

    function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96)
        external onlyPoolManager returns (bytes4)
    {
        return _beforeInitialize(sender, key, sqrtPriceX96);
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24)
        external pure returns (bytes4) { revert HookNotImplemented(); }

    function beforeAddLiquidity(
        address sender, PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params, bytes calldata hookData
    ) external onlyPoolManager returns (bytes4) {
        return _beforeAddLiquidity(sender, key, params, hookData);
    }

    function afterAddLiquidity(
        address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta, BalanceDelta, bytes calldata
    ) external pure returns (bytes4, BalanceDelta) { revert HookNotImplemented(); }

    function beforeRemoveLiquidity(
        address sender, PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params, bytes calldata hookData
    ) external onlyPoolManager returns (bytes4) {
        return _beforeRemoveLiquidity(sender, key, params, hookData);
    }

    function afterRemoveLiquidity(
        address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta, BalanceDelta, bytes calldata
    ) external pure returns (bytes4, BalanceDelta) { revert HookNotImplemented(); }

    function beforeSwap(
        address sender, PoolKey calldata key,
        IPoolManager.SwapParams calldata params, bytes calldata hookData
    ) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        return _beforeSwap(sender, key, params, hookData);
    }

    function afterSwap(
        address, PoolKey calldata, IPoolManager.SwapParams calldata,
        BalanceDelta, bytes calldata
    ) external pure returns (bytes4, int128) { revert HookNotImplemented(); }

    function beforeDonate(
        address sender, PoolKey calldata key,
        uint256 amount0, uint256 amount1, bytes calldata hookData
    ) external onlyPoolManager returns (bytes4) {
        return _beforeDonate(sender, key, amount0, amount1, hookData);
    }

    function afterDonate(
        address, PoolKey calldata, uint256, uint256, bytes calldata
    ) external pure returns (bytes4) { revert HookNotImplemented(); }

    // ---- Subclass overrides ----

    function _beforeInitialize(address, PoolKey calldata, uint160)
        internal virtual returns (bytes4) { revert HookNotImplemented(); }

    function _beforeAddLiquidity(
        address, PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata, bytes calldata
    ) internal virtual returns (bytes4) { revert HookNotImplemented(); }

    function _beforeRemoveLiquidity(
        address, PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata, bytes calldata
    ) internal virtual returns (bytes4) { revert HookNotImplemented(); }

    function _beforeSwap(
        address, PoolKey calldata,
        IPoolManager.SwapParams calldata, bytes calldata
    ) internal virtual returns (bytes4, BeforeSwapDelta, uint24) { revert HookNotImplemented(); }

    function _beforeDonate(
        address, PoolKey calldata, uint256, uint256, bytes calldata
    ) internal virtual returns (bytes4) { revert HookNotImplemented(); }
}
