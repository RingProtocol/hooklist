// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../library/IRandomSeedProvider.sol";

/// @dev простой мок для тестов: возвращает block.timestamp как сид
contract RandomSeedProviderMock is IRandomSeedProvider {
    uint256 private _seed;

    function randomSeed() external view override returns (uint256) {
        return _seed;
    }

    function setSeed(uint256 seed) external {
        _seed = seed;
    }
}
