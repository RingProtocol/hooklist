// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Generation parameters (element counts and palette sizes).
/// Field names match the user-facing trait labels exposed via UoreLens.
struct ImageParams {
    // palette sizes
    uint8 colorsCount;             // full color palette
    uint8 backgroundColorsCount;   // background palette

    // element counts per layer
    uint mouthCount;       // (was: accessoriesCount)
    uint skinCount;        // (was: bodyCount)
    uint eyesCount;
    uint crownCount;       // (was: hairCount)
    uint earCount;         // (was: hornCount)
    uint faceCount;        // (was: legsFrontCount)
    uint reserved1Count;   // unused (was: legsBackCount)
    uint toolCount;        // (was: tailCount)
    uint reserved2Count;   // unused (was: groundCount)
    uint clothCount;       // (was: wingsCount)
}

interface IImageParams {
    /// @dev Returns aggregated parameters for seed/Upeg generation.
    function getImageParams() external view returns (ImageParams memory);
}
