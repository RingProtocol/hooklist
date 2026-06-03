// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Metadata structure for Upeg.
/// If a value is 0, the item is absent in Upeg.
/// Field names match the user-facing trait labels exposed via UoreLens.
struct UpegMetadata {
    uint8 background;       // background color (can be 0)
    uint8 skin;             // head + torso silhouette (was: body)
    uint8 eyes;
    uint8 crown;            // hats / hairstyles / halos (was: hair)
    uint8 ear;              // earring (was: horn)
    uint8 reserved1;        // unused (was: legsBack — kept for byte-format compatibility)
    uint8 face;             // face marks / beards / mustaches (was: legsFront)
    uint8 cloth;            // profession outfits (was: wings)
    uint8 tool;             // mining tools held at side (was: tail)
    uint8 mouth;            // cigarette / cigar / lollipop / smirk (was: accessories)
    uint8 reserved2;        // unused (was: ground — kept for byte-format compatibility)
    uint8 skinColor;        // (was: bodyColor)
    uint8 eyesColor;
    uint8 crownColor;       // (was: hairColor)
    uint8 earColor;         // (was: hornColor)
    uint8 reserved2Color;   // unused (was: groundColor)
    uint8 mouthColor;       // (was: accessoriesColor)
    uint8 toolColor;        // (was: tailColor)
}

/// @dev Library for encoding/decoding UpegMetadata into uint256.
/// Each item is omitted if its value is 0.
/// 1 byte  - background color (can be 0)
/// 2 byte  - ear
/// 3 byte  - mouth
/// 4 byte  - crown
/// 5 byte  - cloth
/// 6 byte  - tool
/// 7 byte  - face
/// 8 byte  - reserved1 (was legsBack — unused)
/// 9 byte  - eyes
/// 10 byte - skin
/// 11 byte - reserved2 (was ground — unused)
/// 12 byte - skin color
/// 13 byte - eyes color
/// 14 byte - crown color
/// 15 byte - ear color
/// 16 byte - reserved2 color
/// 17 byte - mouth color
/// 18 byte - tool color
library UpegMetadataLibrary {
    /// @dev Encodes UpegMetadata into uint256.
    function encode(UpegMetadata memory seed) internal pure returns (uint256 result) {
        result |= uint256(seed.background) << 0;
        result |= uint256(seed.ear) << 8;
        result |= uint256(seed.mouth) << 16;
        result |= uint256(seed.crown) << 24;
        result |= uint256(seed.cloth) << 32;
        result |= uint256(seed.tool) << 40;
        result |= uint256(seed.face) << 48;
        result |= uint256(seed.reserved1) << 56;
        result |= uint256(seed.eyes) << 64;
        result |= uint256(seed.skin) << 72;
        result |= uint256(seed.reserved2) << 80;
        result |= uint256(seed.skinColor) << 88;
        result |= uint256(seed.eyesColor) << 96;
        result |= uint256(seed.crownColor) << 104;
        result |= uint256(seed.earColor) << 112;
        result |= uint256(seed.reserved2Color) << 120;
        result |= uint256(seed.mouthColor) << 128;
        result |= uint256(seed.toolColor) << 136;
    }

    /// @dev Decodes uint256 into UpegMetadata.
    function decode(uint256 seed) internal pure returns (UpegMetadata memory) {
        return
            UpegMetadata({
                background: uint8(seed & 0xFF),
                skin: uint8((seed >> 72) & 0xFF),
                eyes: uint8((seed >> 64) & 0xFF),
                crown: uint8((seed >> 24) & 0xFF),
                ear: uint8((seed >> 8) & 0xFF),
                reserved1: uint8((seed >> 56) & 0xFF),
                face: uint8((seed >> 48) & 0xFF),
                cloth: uint8((seed >> 32) & 0xFF),
                tool: uint8((seed >> 40) & 0xFF),
                mouth: uint8((seed >> 16) & 0xFF),
                reserved2: uint8((seed >> 80) & 0xFF),
                skinColor: uint8((seed >> 88) & 0xFF),
                eyesColor: uint8((seed >> 96) & 0xFF),
                crownColor: uint8((seed >> 104) & 0xFF),
                earColor: uint8((seed >> 112) & 0xFF),
                reserved2Color: uint8((seed >> 120) & 0xFF),
                mouthColor: uint8((seed >> 128) & 0xFF),
                toolColor: uint8((seed >> 136) & 0xFF)
            });
    }
}
