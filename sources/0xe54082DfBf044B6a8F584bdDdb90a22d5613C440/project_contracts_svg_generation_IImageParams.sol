// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Generation parameters (element counts and palette sizes).
struct ImageParams {
    // palette sizes
    uint8 colorsCount; // full color palette
    uint8 backgroundColorsCount; // background palette

    // element counts per layer
    uint accessoriesCount;
    uint bodyCount;
    uint eyesCount;
    uint hairCount;
    uint hornCount;
    uint legsFrontCount;
    uint legsBackCount;
    uint tailCount;
    uint groundCount;
    uint wingsCount;
}

interface IImageParams {
    /// @dev Returns aggregated parameters for seed/Upeg generation.
    function getImageParams() external view returns (ImageParams memory);
}


