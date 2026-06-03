// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";

/// Минимальный ERC20 токен для тестов Uniswap v4
contract TestToken is ERC20, Ownable {
    /// начальное количество (для удобства тестов)
    uint256 public constant INITIAL_SUPPLY = 1_000_000e18;

    constructor() {
        _initializeOwner(msg.sender);
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    /// имя токена
    function name() public pure override returns (string memory) { return "Test Token"; }

    /// символ токена
    function symbol() public pure override returns (string memory) { return "TST"; }
}
