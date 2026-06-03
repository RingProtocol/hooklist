// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Metadata structure for Upeg.
/// If a value is 0, the item is absent in Upeg.
struct UpegMetadata {
    uint8 backGroundColor; // background color (can be 0)
    uint8 body;
    uint8 eyes;
    uint8 hair;
    uint8 horn;
    uint8 legsBack;
    uint8 legsFront;
    uint8 wings;
    uint8 tail;
    uint8 accessories;
    uint8 ground;
    uint8 bodyColor; // body color index (legs and wings use the same color)
    uint8 eyesColor;
    uint8 hairColor;
    uint8 hornColor;
    uint8 groundColor;
    uint8 accessoriesColor;
    uint8 tailColor;
}

/// @dev Library for encoding/decoding UpegMetadata into uint256.
/// Each item is omitted if its value is 0.
/// 1 byte  - background color (can be 0)
/// 2 byte  - horn
/// 3 byte  - accessories
/// 4 byte  - hair
/// 5 byte  - wings
/// 6 byte  - tail
/// 7 byte  - front legs
/// 8 byte  - back legs
/// 9 byte  - eyes
/// 10 byte - body
/// 11 byte - ground
/// 12 byte - body color (legs and wings use the same color)
/// 13 byte - eyes color
/// 14 byte - hair color
/// 15 byte - horn color
/// 16 byte - ground color
/// 17 byte - accessories color
/// 18 byte - tail color
library UpegMetadataLibrary {
    /// @dev Encodes UpegMetadata into uint256.
    function encode(UpegMetadata memory seed) internal pure returns (uint256 result) {
        result |= uint256(seed.backGroundColor) << 0;
        result |= uint256(seed.horn) << 8;
        result |= uint256(seed.accessories) << 16;
        result |= uint256(seed.hair) << 24;
        result |= uint256(seed.wings) << 32;
        result |= uint256(seed.tail) << 40;
        result |= uint256(seed.legsFront) << 48;
        result |= uint256(seed.legsBack) << 56;
        result |= uint256(seed.eyes) << 64;
        result |= uint256(seed.body) << 72;
        result |= uint256(seed.ground) << 80;
        result |= uint256(seed.bodyColor) << 88;
        result |= uint256(seed.eyesColor) << 96;
        result |= uint256(seed.hairColor) << 104;
        result |= uint256(seed.hornColor) << 112;
        result |= uint256(seed.groundColor) << 120;
        result |= uint256(seed.accessoriesColor) << 128;
        result |= uint256(seed.tailColor) << 136;
    }

    /// @dev Decodes uint256 into UpegMetadata.
    function decode(uint256 seed) internal pure returns (UpegMetadata memory) {
        return
            UpegMetadata({
                backGroundColor: uint8(seed & 0xFF),
                body: uint8((seed >> 72) & 0xFF),
                eyes: uint8((seed >> 64) & 0xFF),
                hair: uint8((seed >> 24) & 0xFF),
                horn: uint8((seed >> 8) & 0xFF),
                legsBack: uint8((seed >> 56) & 0xFF),
                legsFront: uint8((seed >> 48) & 0xFF),
                wings: uint8((seed >> 32) & 0xFF),
                tail: uint8((seed >> 40) & 0xFF),
                accessories: uint8((seed >> 16) & 0xFF),
                ground: uint8((seed >> 80) & 0xFF),
                bodyColor: uint8((seed >> 88) & 0xFF),
                eyesColor: uint8((seed >> 96) & 0xFF),
                hairColor: uint8((seed >> 104) & 0xFF),
                hornColor: uint8((seed >> 112) & 0xFF),
                groundColor: uint8((seed >> 120) & 0xFF),
                accessoriesColor: uint8((seed >> 128) & 0xFF),
                tailColor: uint8((seed >> 136) & 0xFF)
            });
    }
}
