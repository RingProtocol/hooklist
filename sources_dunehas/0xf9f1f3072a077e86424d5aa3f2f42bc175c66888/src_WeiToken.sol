// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Wei — project website: https://0xwei.com

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title WeiToken
/// @notice Plain ERC-20 with one designated minter that is locked in once and cannot be changed.
///         No owner. No pause. No blacklist. No fee logic. No upgrade path. The minter is the
///         only entity allowed to `mint` or `burn`; both buy-side mints and sell-side redemption
///         burns are mediated by `WeiHook`. Protocol fees are routed to a permanent black-hole
///         address (which does NOT decrement totalSupply); redemption burns from the curve do.
contract WeiToken is ERC20 {
    /// @notice The designated minter (the WeiHook). Locked once `setMinter` is called.
    address public minter;

    /// @notice The address that deployed this contract (only entity allowed to set the minter once).
    address public immutable DEPLOYER;

    /// @notice Marker that asserts this contract makes no use of any restriction primitive.
    bool public immutable RESTRICTIONS_FORBIDDEN = true;

    /// @notice The block at which this contract was deployed.
    uint256 public immutable GENESIS_BLOCK;

    /// @notice The hash of the block immediately preceding deployment. Burned into bytecode.
    bytes32 public immutable GENESIS_HASH;

    error NotDeployer();
    error NotMinter();
    error MinterAlreadySet();
    error MinterIsZero();

    event MinterLocked(address indexed minter);

    constructor() ERC20("Wei", "WEI") {
        DEPLOYER = msg.sender;
        GENESIS_BLOCK = block.number;
        // `blockhash(0 - 1)` underflows on a pristine chain (e.g. local anvil).
        // On any real chain block.number is always > 0 at deploy time, so the
        // ternary is purely for local-tool resilience.
        GENESIS_HASH = block.number == 0 ? bytes32(0) : blockhash(block.number - 1);
    }

    /// @notice Set the minter exactly once, then lock forever.
    function setMinter(address newMinter) external {
        if (msg.sender != DEPLOYER) revert NotDeployer();
        if (minter != address(0)) revert MinterAlreadySet();
        if (newMinter == address(0)) revert MinterIsZero();
        minter = newMinter;
        emit MinterLocked(newMinter);
    }

    /// @notice Mint WEI. Callable only by the locked-in minter.
    function mint(address to, uint256 amount) external {
        if (msg.sender != minter) revert NotMinter();
        _mint(to, amount);
    }

    /// @notice Burn WEI from the minter's own balance. Callable only by the locked-in minter.
    ///         Used by `WeiHook._executeSell` for the redemption side of a sell: tokens are
    ///         pulled from the PoolManager into the hook and then permanently destroyed,
    ///         reducing totalSupply. Protocol fees do NOT take this path; they are sent to
    ///         the black-hole address instead, leaving totalSupply untouched.
    function burn(uint256 amount) external {
        if (msg.sender != minter) revert NotMinter();
        _burn(msg.sender, amount);
    }
}
