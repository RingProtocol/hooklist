// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../library/StringConverter.sol";

/// @dev Rectangle.
struct Rect {
    uint8 x;
    uint8 y;
    uint8 width;
    uint8 height;
    uint8 colorIdx;
}

library SvgRects {
    using SvgRects for Rect;
    using StringConverter for uint8;

    function toSvg(
        Rect memory r,
        string memory color
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "<rect x='",
                    r.x.toString(),
                    "' y='",
                    r.y.toString(),
                    "' width='",
                    r.width.toString(),
                    "' height='",
                    r.height.toString(),
                    "' fill='",
                    color,
                    "'/>"
                )
            );
    }

    function toSvg(
        Rect[] storage rects,
        string memory color
    ) internal view returns (string memory) {
        string memory res;
        for (uint i = 0; i < rects.length; ++i) {
            res = string(abi.encodePacked(res, rects[i].toSvg(color)));
        }
        return res;
    }
}
