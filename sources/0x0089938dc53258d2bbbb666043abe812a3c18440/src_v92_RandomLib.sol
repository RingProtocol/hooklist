// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Pseudo-random generator state (mirrors Unipeg).
struct Random {
    uint seed;
    uint nonce;
}

library RandomLibrary {
    function next(Random memory random) internal pure returns (uint) {
        return uint(keccak256(abi.encodePacked(random.seed, ++random.nonce)));
    }
}

interface IRandomSeedProvider {
    function randomSeed() external view returns (uint256);
}
