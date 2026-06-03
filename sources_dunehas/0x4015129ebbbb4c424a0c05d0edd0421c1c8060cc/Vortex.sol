// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Vortex — single-use ETH portal for atomic wallet rotation.
/// @notice Deploy a fresh instance via CREATE2 per rotation. Anyone with the
/// matching `key` for a given `to` address can drain the contract's full ETH
/// balance to `to`. The seal is `keccak256(abi.encode(key, to))`, computed
/// off-chain at deploy time, so only the holder of `key` + the intended `to`
/// can pierce it. After piercing, the contract is empty and economically dead.
///
/// On-chain trail: source funds Vortex, target receives ETH from Vortex. The
/// source ↔ target link is hidden behind a one-shot, address-unique contract.
contract Vortex {
    /// @dev Seal commits to (key, to) at construction so the redeem can be
    /// authorized by anyone knowing both — typically the source EOA that
    /// generated the key for a chosen `to`.
    bytes32 private immutable seal;

    error InvalidKey();
    error EmptyVortex();
    error TransferFailed();

    event Drained(address indexed to, uint256 amount);

    constructor(bytes32 _seal) payable {
        seal = _seal;
    }

    /// @dev Plain ETH receive — anyone can fund the vortex prior to piercing.
    receive() external payable {}

    /// @notice Drain the entire ETH balance to `to`. Anyone may call provided
    /// they present `key` such that `keccak256(abi.encode(key, to)) == seal`.
    /// @param key the secret committed at deploy time (with `to`).
    /// @param to recipient of the ETH; must match the address baked into seal.
    function pierce(bytes32 key, address payable to) external {
        if (keccak256(abi.encode(key, to)) != seal) revert InvalidKey();
        uint256 bal = address(this).balance;
        if (bal == 0) revert EmptyVortex();
        (bool ok, ) = to.call{value: bal}("");
        if (!ok) revert TransferFailed();
        emit Drained(to, bal);
    }
}
