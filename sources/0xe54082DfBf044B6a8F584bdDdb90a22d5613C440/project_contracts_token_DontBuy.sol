// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "solady/src/tokens/ERC20.sol";
import "solady/src/auth/Ownable.sol";

contract DontBuy is ERC20, Ownable {
    uint256 public constant INITIAL_SUPPLY = 1_000_000e18;

    constructor() {
        _initializeOwner(msg.sender);
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function name() public pure override returns (string memory) { return "Don't Buy"; }
    
    function symbol() public pure override returns (string memory) { return "TESTHOOK"; }
}