// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../upegs/Upeg.sol";
import "../../library/Ownable.sol";

/// @dev тестовый контракт-обёртка, раскрывающий внутренние методы для тестирования
contract UpegTest is Upeg, Ownable {
    /// @dev публично вызывает внутренний генератор Upeg и возвращает закодированный сид
    function nextUpeg() external view returns (uint256) {
        return _nextUpeg(createRandom());
    }

    /// @dev публично создаёт Upeg для адреса (используя внутреннюю логику)
    function mintUpegMock(address owner) external onlyOwner {
        _mintUpeg(owner, createRandom());
    }

    /// @dev устанавливает источник параметров изображений
    /// @param imageParamsProvider адрес контракта, реализующего IImageParams
    function setImageParamsProvider(address imageParamsProvider) external onlyOwner {
        _setImageParamsProvider(imageParamsProvider);
    }

    /// @dev устанавливает источник сида для генерации случайных чисел
    /// @param randomSeedProvider_ адрес контракта, реализующего IRandomSeedProvider
    function setRandomSeedProvider(address randomSeedProvider_) external onlyOwner {
        _setRandomSeedProvider(randomSeedProvider_);
    }
}


