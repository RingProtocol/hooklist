// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IRandomSeedProvider {
    function seed() external view returns (uint256);
}
