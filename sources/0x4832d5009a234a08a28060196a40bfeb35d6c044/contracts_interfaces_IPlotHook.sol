// SPDX-License-Identifier: MIT
//
//    UniLand — random plot lottery powered by a Uniswap V4 hook
//      X       : https://x.com/UniLandHooks
//      Website : https://unilandhooks.fun
//
pragma solidity ^0.8.26;

interface IPlotHook {
    /// @notice Latest entropy seed accumulated from all swaps.
    function seed() external view returns (uint256);

    /// @notice Total number of swaps that have updated the seed.
    function swapNonce() external view returns (uint64);

    /// @notice Address of the PlotToken bound to this hook.
    function plotToken() external view returns (address);

    /// @notice One-shot binding. Caller must equal `_token`.
    function setPlotToken(address _token) external;

    /// @notice Cumulative ETH tax routed (in wei).
    function totalTaxCollected() external view returns (uint256);

    /// @notice Cumulative ETH tax routed to treasury (subset of `totalTaxCollected`).
    function totalTaxToTreasury() external view returns (uint256);
}
