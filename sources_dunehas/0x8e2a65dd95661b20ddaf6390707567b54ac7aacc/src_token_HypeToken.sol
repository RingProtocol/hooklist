// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "solady/src/tokens/ERC20.sol";

/// @notice Plain fixed-supply ERC20. No mint/burn surface — the full supply is
///         minted once to the hook at construction and lives as bonding-curve
///         band liquidity + leveraged-position holdings + reserve from there on.
contract HypeToken is ERC20 {
    string private constant _NAME   = "Uniperp";
    string private constant _SYMBOL = "PERP";
    uint256 public constant TOTAL_SUPPLY = 1_000_000 ether;

    error ZeroAddress();

    constructor(address recipient) {
        if (recipient == address(0)) revert ZeroAddress();
        _mint(recipient, TOTAL_SUPPLY);
    }

    function name() public pure override returns (string memory) {
        return _NAME;
    }

    function symbol() public pure override returns (string memory) {
        return _SYMBOL;
    }
}
