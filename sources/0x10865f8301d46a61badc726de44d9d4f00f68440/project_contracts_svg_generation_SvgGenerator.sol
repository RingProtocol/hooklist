// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SvgRects.sol";
import "./UpegMetadata.sol";
import "../library/OwnableBase.sol";
import "./IImageParams.sol";

/// @dev File data.
struct FileData {
    uint id;
    Rect[] rects;
}

/// @dev Data input helper library.
library InputDataLibrary {
    function set(
        mapping(uint id => Rect[]) storage stor,
        FileData[] memory rects
    ) internal returns (uint) {
        uint count = 0;
        for (uint i = 0; i < rects.length; i++) {
            if (stor[rects[i].id].length == 0) count++;
            else delete stor[rects[i].id];
            for (uint j = 0; j < rects[i].rects.length; j++) {
                stor[rects[i].id].push(rects[i].rects[j]);
            }
        }
        return count;
    }
}

/// @dev Contract for Upeg generation.
contract SvgGenerator is OwnableBase, IImageParams {
    uint8 private constant SVG_SIZE = 24;

    /// @dev Size of the main color palette.
    uint8 constant COLORS_COUNT = 36;
    /// @dev Size of the background palette.
    uint8 constant BACKGROUND_COLORS_COUNT = 6;

    /// @dev Unified color palette (0 disables a layer; indices are modulo COLORS_COUNT).
    string[COLORS_COUNT] private colors = [
        "#a9b6d2",
        "#cbdbfc",
        "#eae1b5",
        "#d9a066",
        "#9dcde4",
        "#8f563b",
        "#524b24",
        "#ac3232",
        "#d77bba",
        "#847e87",
        "#626979",
        "#306082",
        "#323c39",
        "#306082",
        "#6e3e54",
        "#cb67d2",
        "#37946e",
        "#df7126",
        "#d95763",
        "#5fcde4",
        "#d2ac8d",
        "#cbdbfc",
        "#696a6a",
        "#e7d632",
        "#e76232",
        "#cee6f3",
        "#e79090",
        "#fcf893",
        "#edb187",
        "#b3dcf7",
        "#4b8b3b",
        "#7fc97f",
        "#1e1e26",
        "#2d1b1b",
        "#a0a0a0",
        "#00ffd0"
    ];

    /// @dev Separate palette for background (indices are modulo BACKGROUND_COLORS_COUNT).
    string[BACKGROUND_COLORS_COUNT] private backgroundColors = [
        "#1a1c2c",
        "#3a3f58",
        "#cbbba0",
        "#7a8ca8",
        "#394b3f",
        "#2e243f"
    ];

    /// @dev Mappings with image parts.
    mapping(uint => Rect[]) _accessories;
    mapping(uint => Rect[]) _body;
    mapping(uint => Rect[]) _eyes;
    mapping(uint => Rect[]) _hair;
    mapping(uint => Rect[]) _horn;
    mapping(uint => Rect[]) _legsFront;
    mapping(uint => Rect[]) _legsBack;
    mapping(uint => Rect[]) _tail;
    mapping(uint => Rect[]) _ground;
    mapping(uint => Rect[]) _wings;

    uint public accessoriesCount;
    uint public bodyCount;
    uint public eyesCount;
    uint public hairCount;
    uint public hornCount;
    uint public legsFrontCount;
    uint public legsBackCount;
    uint public tailCount;
    uint public groundCount;
    uint public wingsCount;

    constructor(address owner_) OwnableBase(owner_) {}

    /// @dev Sets data for image parts.
    function setAccessories(FileData[] memory rects) public onlyOwner {
        accessoriesCount += InputDataLibrary.set(_accessories, rects);
    }

    function setBody(FileData[] memory rects) public onlyOwner {
        bodyCount += InputDataLibrary.set(_body, rects);
    }

    function setEyes(FileData[] memory rects) public onlyOwner {
        eyesCount += InputDataLibrary.set(_eyes, rects);
    }

    function setHair(FileData[] memory rects) public onlyOwner {
        hairCount += InputDataLibrary.set(_hair, rects);
    }

    function setHorn(FileData[] memory rects) public onlyOwner {
        hornCount += InputDataLibrary.set(_horn, rects);
    }

    function setLegsFront(FileData[] memory rects) public onlyOwner {
        legsFrontCount += InputDataLibrary.set(_legsFront, rects);
    }

    function setLegsBack(FileData[] memory rects) public onlyOwner {
        legsBackCount += InputDataLibrary.set(_legsBack, rects);
    }

    function setTail(FileData[] memory rects) public onlyOwner {
        tailCount += InputDataLibrary.set(_tail, rects);
    }

    function setGround(FileData[] memory rects) public onlyOwner {
        groundCount += InputDataLibrary.set(_ground, rects);
    }

    function setWings(FileData[] memory rects) public onlyOwner {
        wingsCount += InputDataLibrary.set(_wings, rects);
    }

    function toString(uint value) private pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint temp = value;
        uint digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

/// @dev Returns Upeg metadata from a seed.
/// @param seed Seed value.
/// @return Upeg metadata.
function getSeedData(uint256 seed) public pure returns (UpegMetadata memory) {
        return UpegMetadataLibrary.decode(seed);
    }

/// @dev Generates SVG from a seed.
/// @param seed Upeg seed.
/// @return SVG string.
function generate(uint256 seed) public view returns (string memory) {
    UpegMetadata memory seedData = UpegMetadataLibrary.decode(seed);
        return generateSvg(seedData);
    }

/// @dev Generates SVG from Upeg metadata.
/// @param seedData Upeg metadata.
/// @return SVG string.
function generateSvg(
    UpegMetadata memory seedData
    ) public view returns (string memory) {
        // Build a simple layered SVG where each non-zero layer overlays the previous.
        string memory svg = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0",
            " ",
            toString(SVG_SIZE),
            " ",
            toString(SVG_SIZE),
            "'>"
        );

        // Static background for the whole canvas.
        svg = string.concat(
            svg,
            SvgRects.toSvg(
                Rect({x: 0, y: 0, width: SVG_SIZE, height: SVG_SIZE}),
                backgroundColors[
                    seedData.backGroundColor % BACKGROUND_COLORS_COUNT
                ]
            )
        );

        if (seedData.body > 0)
            svg = string.concat(
                svg,
                SvgRects.toSvg(
                    _body[seedData.body],
                    colors[seedData.bodyColor % COLORS_COUNT]
                )
            );
        if (seedData.horn > 0)
            svg = string.concat(
                svg,
                SvgRects.toSvg(
                    _horn[seedData.horn],
                    colors[seedData.hornColor % COLORS_COUNT]
                )
            );
        if (seedData.accessories > 0)
            svg = string.concat(
                svg,
                SvgRects.toSvg(
                    _accessories[seedData.accessories],
                    colors[seedData.accessoriesColor % COLORS_COUNT]
                )
            );
        if (seedData.wings > 0)
            svg = string.concat(
                svg,
                SvgRects.toSvg(
                    _wings[seedData.wings],
                    colors[seedData.bodyColor % COLORS_COUNT]
                )
            );
        if (seedData.hair > 0)
            svg = string.concat(
                svg,
                SvgRects.toSvg(
                    _hair[seedData.hair],
                    colors[seedData.hairColor % COLORS_COUNT]
                )
            );
        if (seedData.tail > 0)
            svg = string.concat(
                svg,
                SvgRects.toSvg(
                    _tail[seedData.tail],
                    colors[seedData.tailColor % COLORS_COUNT]
                )
            );
        if (seedData.legsFront > 0)
            svg = string.concat(
                svg,
                SvgRects.toSvg(
                    _legsFront[seedData.legsFront],
                    colors[seedData.bodyColor % COLORS_COUNT]
                )
            );
        if (seedData.legsBack > 0)
            svg = string.concat(
                svg,
                SvgRects.toSvg(
                    _legsBack[seedData.legsBack],
                    colors[seedData.bodyColor % COLORS_COUNT]
                )
            );
        if (seedData.ground > 0)
            svg = string.concat(
                svg,
                SvgRects.toSvg(
                    _ground[seedData.ground],
                    colors[seedData.groundColor % COLORS_COUNT]
                )
            );
        if (seedData.eyes > 0)
            svg = string.concat(
                svg,
                SvgRects.toSvg(
                    _eyes[seedData.eyes],
                    colors[seedData.eyesColor % COLORS_COUNT]
                )
            );

        svg = string.concat(svg, "</svg>");
        return svg;
    }

    /// @dev Returns aggregated parameters for seed/Upeg generation.
    function getImageParams() external view override returns (ImageParams memory) {
        return ImageParams({
            colorsCount: COLORS_COUNT,
            backgroundColorsCount: BACKGROUND_COLORS_COUNT,
            accessoriesCount: accessoriesCount,
            bodyCount: bodyCount,
            eyesCount: eyesCount,
            hairCount: hairCount,
            hornCount: hornCount,
            legsFrontCount: legsFrontCount,
            legsBackCount: legsBackCount,
            tailCount: tailCount,
            groundCount: groundCount,
            wingsCount: wingsCount
        });
    }
}
