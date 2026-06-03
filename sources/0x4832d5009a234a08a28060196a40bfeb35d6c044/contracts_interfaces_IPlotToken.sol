// SPDX-License-Identifier: MIT
//
//    UniLand — random plot lottery powered by a Uniswap V4 hook
//      X       : https://x.com/UniLandHooks
//      Website : https://unilandhooks.fun
//
pragma solidity ^0.8.26;

interface IPlotToken {
    /* ------------------------------------------------------------------ */
    /*  Events                                                            */
    /* ------------------------------------------------------------------ */
    event PlotsAllocated(address indexed to, uint32[] plotIds, uint256 entropy);
    event PlotsReleased(address indexed from, uint32[] plotIds);

    /* ------------------------------------------------------------------ */
    /*  Plot ledger views                                                 */
    /* ------------------------------------------------------------------ */
    function plotOwner(uint32 plotId) external view returns (address);
    function plotsOf(address account) external view returns (uint32[] memory);
    function plotCountOf(address account) external view returns (uint256);
    function freePlots() external view returns (uint32);
    function totalPlots() external view returns (uint32);

    function plotOwnersRange(uint32 start, uint32 count)
        external view returns (address[] memory);

    function plotOwnedBitmap(uint32 start) external view returns (uint256);
}
