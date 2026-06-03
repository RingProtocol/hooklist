// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC3232Hook} from "./interfaces/IERC3232Hook.sol";
import {IHooks} from "v4-core-4.0.0/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core-4.0.0/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core-4.0.0/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core-4.0.0/src/types/PoolId.sol";
import {Currency} from "v4-core-4.0.0/src/types/Currency.sol";
import {BalanceDelta} from "v4-core-4.0.0/src/types/BalanceDelta.sol";
import {Ownable} from "@openzeppelin-contracts-5.0.2/access/Ownable.sol";

/// @title HookdRandomHook
/// @notice Reusable v4 hook that records one rolling swap seed per ERC3232 token.
/// @dev The hook intentionally does not mint objects. It only observes canonical pool swaps and updates
///      `lastSeed[token]`; the token reads that seed during its PoolManager-triggered ERC20 transfer.
contract HookdRandomHook is IERC3232Hook, Ownable {
    using PoolIdLibrary for PoolKey;

    error FactoryAlreadySet(address factory);
    error InvalidPool();
    error NoHookToken();
    error OnlyFactory(address caller, address factory);
    error OnlyPoolManager();
    error UnauthorizedInit();
    error ZeroAddress();

    IPoolManager public immutable poolManager;
    address public factory;
    mapping(address token => bytes32 seed) private _lastSeeds;
    mapping(bytes32 poolId => bool authorized) private _authorizedPoolIds;

    constructor(IPoolManager poolManager_, address initialOwner) Ownable(initialOwner) {
        if (address(poolManager_) == address(0) || initialOwner == address(0)) revert ZeroAddress();
        poolManager = poolManager_;
    }

    /// @notice One-time factory assignment. Only this factory can authorize pool initializations.
    function setFactory(address factory_) external onlyOwner {
        if (factory != address(0)) revert FactoryAlreadySet(factory);
        if (factory_ == address(0)) revert ZeroAddress();
        factory = factory_;
    }

    /// @notice Pre-authorizes a specific pool key for initialization. Must be called by the factory
    ///         immediately before positionManager.initializePool in the same transaction.
    function authorizePoolInit(PoolKey calldata key) external {
        if (msg.sender != factory) revert OnlyFactory(msg.sender, factory);
        _authorizedPoolIds[PoolId.unwrap(key.toId())] = true;
    }

    /// @notice Rejects pool initialization unless the factory pre-authorized this exact pool key.
    ///         This prevents anyone from initializing a pool with this hook at an arbitrary price.
    function beforeInitialize(address, PoolKey calldata key, uint160) external onlyPoolManager returns (bytes4) {
        bytes32 poolId = PoolId.unwrap(key.toId());
        if (!_authorizedPoolIds[poolId]) revert UnauthorizedInit();
        delete _authorizedPoolIds[poolId];
        return IHooks.beforeInitialize.selector;
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        _;
    }

    /// @notice Returns the latest hook-maintained seed for the calling token.
    /// @dev Tokens call this while deriving object seeds. The caller is used as the lookup key so one hook can be
    ///      shared by many Hookd/ERC3232 tokens without exposing a token argument that could be spoofed.
    function randomSeed() external view returns (bytes32) {
        return _lastSeedFor(msg.sender);
    }

    /// @notice Reusable hooks are not tied to a single pool id.
    /// @dev This satisfies the shared hook/token interface. Pool restriction lives on the token side:
    ///      `HookdToken.generationPoolId()` returns the canonical pool id after launch.
    function generationPoolId() external pure returns (bytes32) {
        return bytes32(0);
    }

    /// @notice Updates the generation seed after swaps that output or input the configured token.
    /// @dev The hook address only carries the `AFTER_SWAP` permission bit, so v4 only calls this callback.
    ///      `_hookToken` finds the ERC3232-aware currency and verifies that the pool id matches that token's
    ///      configured generation pool before any seed is updated.
    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, int128) {
        (address token, bytes32 poolId) = _hookToken(key);
        _updateSeed(token, sender, key, params, delta, poolId);

        return (IHooks.afterSwap.selector, 0);
    }

    function _updateSeed(
        address token,
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes32 poolId
    ) internal {
        bytes32 previousSeed = _lastSeedFor(token);
        // The seed is a rolling hash. Including the previous seed makes each swap depend on all prior swaps for
        // this token, while the pool, params, and delta bind the update to the actual v4 swap that just settled.
        _lastSeeds[token] = keccak256(
            abi.encode(
                "ERC3232_SWAP_RANDOM_SEED",
                previousSeed,
                address(this),
                token,
                sender,
                poolId,
                Currency.unwrap(key.currency0),
                Currency.unwrap(key.currency1),
                key.fee,
                key.tickSpacing,
                params.zeroForOne,
                params.amountSpecified,
                params.sqrtPriceLimitX96,
                delta.amount0(),
                delta.amount1(),
                block.number,
                block.chainid
            )
        );
    }

    function _hookToken(PoolKey calldata key) internal view returns (address target, bytes32 actualPoolId) {
        actualPoolId = PoolId.unwrap(key.toId());

        address currency0 = Currency.unwrap(key.currency0);
        address currency1 = Currency.unwrap(key.currency1);

        // Native ETH and ordinary ERC20s will fail this staticcall. Hookd/ERC3232 tokens implement
        // `generationPoolId()`, which lets the reusable hook identify the token side of the pool.
        (bool success, bytes32 expectedPoolId) = _generationPoolId(currency0);
        if (success) {
            _validateGenerationPool(expectedPoolId, actualPoolId);
            return (currency0, actualPoolId);
        }

        (success, expectedPoolId) = _generationPoolId(currency1);
        if (success) {
            _validateGenerationPool(expectedPoolId, actualPoolId);
            return (currency1, actualPoolId);
        }

        revert NoHookToken();
    }

    function _generationPoolId(address candidate) internal view returns (bool success, bytes32 poolId) {
        bytes memory data;
        (success, data) = candidate.staticcall(abi.encodeCall(IERC3232Hook.generationPoolId, ()));
        if (!success || data.length != 32) return (false, bytes32(0));
        poolId = abi.decode(data, (bytes32));
    }

    function _validateGenerationPool(bytes32 expectedPoolId, bytes32 actualPoolId) internal pure {
        // A zero expected pool id means "unrestricted". HookdToken sets a non-zero pool id in `start`, so
        // deployed Hookd drops only accept swaps from their canonical factory-configured pool.
        if (expectedPoolId != bytes32(0) && expectedPoolId != actualPoolId) revert InvalidPool();
    }

    function _lastSeedFor(address target) internal view returns (bytes32 seed) {
        seed = _lastSeeds[target];
        if (seed == bytes32(0)) {
            // Before the first swap, expose a deterministic non-zero seed so token generation can still fold in a
            // hook seed without special-casing zero.
            seed = keccak256(abi.encode("ERC3232_INITIAL_RANDOM_SEED", address(this), target, block.chainid));
        }
    }
}
