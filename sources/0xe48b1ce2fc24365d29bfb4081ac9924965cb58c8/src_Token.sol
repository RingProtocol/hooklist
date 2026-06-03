// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "solady/tokens/ERC20.sol";

/// @title Token
/// @notice SPIN ERC-20 token with on-demand minting. Total supply starts at 0 and grows via bonding curve.
contract Token is ERC20 {
    uint256 public constant MAX_SUPPLY = 3**21 * 1e18;

    address public hook;

    error HookAlreadySet();
    error ZeroAddress();
    error OnlyHook();
    error ExceedsMaxSupply();

    event HookLocked(address indexed hook);

    modifier onlyHook() {
        if (msg.sender != hook) revert OnlyHook();
        _;
    }

    constructor() {}

    /// @notice One-time setup: assign the Hook contract address. Called from Hook constructor.
    ///         Protected by one-time check — front-running is prevented by deploying Token
    ///         and Hook atomically in the same transaction.
    function setHook(address hook_) external {
        if (hook != address(0)) revert HookAlreadySet();
        if (hook_ == address(0)) revert ZeroAddress();
        hook = hook_;
        emit HookLocked(hook_);
    }

    /// @notice Hook mints SPIN when users buy on the bonding curve.
    function mint(address to, uint256 amount) external onlyHook {
        if (to == address(0)) revert ZeroAddress();
        if (totalSupply() + amount > MAX_SUPPLY) revert ExceedsMaxSupply();
        _mint(to, amount);
    }

    /// @notice Hook burns SPIN from its own balance when users sell.
    function burn(address from, uint256 amount) external onlyHook {
        _burn(from, amount);
    }

    function name() public pure override returns (string memory) {
        return "Spinance";
    }

    function symbol() public pure override returns (string memory) {
        return "SPIN";
    }
}
