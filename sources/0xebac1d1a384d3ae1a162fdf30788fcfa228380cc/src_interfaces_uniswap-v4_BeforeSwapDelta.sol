// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

type BeforeSwapDelta is int256;

library BeforeSwapDeltaLibrary {
    BeforeSwapDelta public constant ZERO_DELTA = BeforeSwapDelta.wrap(0);
}

/// @notice Helper to construct a BeforeSwapDelta from specified and unspecified deltas
function toBeforeSwapDelta(int128 deltaSpecified, int128 deltaUnspecified)
    pure
    returns (BeforeSwapDelta)
{
    return BeforeSwapDelta.wrap(
        (int256(deltaSpecified) << 128) | int256(uint256(uint128(deltaUnspecified)))
    );
}

