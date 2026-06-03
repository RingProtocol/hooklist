// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Hookd random hook extension interface
/// @notice Shared interface for hook-aware ERC3232 implementations.
interface IERC3232Hook {
    /// @notice Returns the pool id allowed to trigger automatic object generation, or zero if unrestricted.
    function generationPoolId() external view returns (bytes32);

    /// @notice Returns the latest hook-maintained seed.
    function randomSeed() external view returns (bytes32);
}
