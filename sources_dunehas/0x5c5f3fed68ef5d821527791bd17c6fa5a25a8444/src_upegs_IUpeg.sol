// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Upeg data structure.
struct UpegSeedData {
    /// @dev Upeg ID.
    uint256 id;
    /// @dev Upeg seed.
    uint256 seed;
}

/// @dev Upeg collection interface.
/// Each owner has a list of Upegs with unique IDs and seed values.
interface IUpeg {
    /// @dev Error when the caller doesn't own the Upeg.
    error NotUpegOwner();
    /// @dev Error when Upeg index is out of range.
    error UpegIndexOutOfRange();

    /// @dev Upeg mint event.
    event OnUpegMinted(address indexed owner, uint upegId);
    /// @dev Upeg burn event.
    event OnUpegBurned(address indexed owner, uint upegId);
    /// @dev Upeg transfer event.
    event OnUpegTransfer(address indexed from, address indexed to, uint upegId);

    /// @dev Total Upeg count.
    function UpegsTotalCount() external view returns (uint);
    /// @dev Total holder count.
    function HoldersCount() external view returns (uint);
    /// @dev Upeg count for an owner.
    function OwnerUpegsCount(address owner) external view returns (uint);
    /// @dev Returns a paginated list of Upegs.
    /// @param owner Owner address
    /// @param page Page number
    /// @param pageSize Page size
    function OwnerUpegsPage(address owner, uint page, uint pageSize) external view returns (UpegSeedData[] memory upegs);
    /// @dev Upeg for an owner by index.
    /// @param owner Owner address
    /// @param index Upeg index
    function OwnerUpeg(address owner, uint index) external view returns (UpegSeedData memory);
    /// @dev Upeg index for an owner by ID.
    /// @param owner Owner address
    /// @param upegId Upeg ID
    function OwnerUpegIndex(address owner, uint upegId) external view returns (uint index);
    /// @dev Reorders the caller's Upeg. Shifts all items left/right (may be gas-inefficient).
    /// @param upegId Upeg ID to reorder
    /// @param newIndex New index
    function ReorderUpeg(uint upegId, uint newIndex) external;
    /// @dev Reorders the caller's Upeg. Gas-optimized swap without shifting.
    /// @param upegId Upeg ID to reorder
    /// @param newIndex New index or swap index
    function ReorderUpegPair(uint upegId, uint newIndex) external;
    /// @dev Checks if the owner owns a Upeg by ID.
    function OwnerOwns(address owner, uint upegId) external view returns (bool);
    /// @dev Checks if the owner is a holder.
    function IsHolder(address owner) external view returns (bool);
    /// @dev Holder by index.
    function Holder(uint index) external view returns (address);
    /// @dev Holder number by address.
    function HolderNumber(address owner) external view returns (uint);

    /// @dev Transfers a Upeg to an address. One token is transferred with the Upeg.
    /// @param to Recipient address
    /// @param upegId Upeg ID
    function transferUpeg(address to, uint upegId) external;
    /// @dev Transfers multiple Upegs. Transfers the same number of tokens.
    /// @param to Recipient address
    /// @param upegIds Array of Upeg IDs
    function transferUpegsList(
        address to,
        uint[] calldata upegIds
    ) external;
}