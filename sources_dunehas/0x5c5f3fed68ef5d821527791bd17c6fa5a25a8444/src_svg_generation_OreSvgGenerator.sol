// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SvgRects.sol";
import "./UpegMetadata.sol";
import "../library/OwnableBase.sol";
import "./IImageParams.sol";

interface IUoreRenderView {
    function upegSeedOf(uint256 upegId) external view returns (uint256);

    function getClass(uint256 upegId) external view returns (uint8);
}

struct FileData {
    uint256 id;
    Rect[] rects;
}

library InputDataLibrary {
    function set(
        mapping(uint256 => Rect[]) storage stor,
        FileData[] memory files
    ) internal returns (uint256) {
        uint256 count;
        for (uint256 i; i < files.length; ++i) {
            if (stor[files[i].id].length == 0) count++;
            else delete stor[files[i].id];
            for (uint256 j; j < files[i].rects.length; ++j) {
                stor[files[i].id].push(files[i].rects[j]);
            }
        }
        return count;
    }
}

contract OreSvgGenerator is OwnableBase, IImageParams {
    using SvgRects for Rect;

    uint8 private constant SVG_SIZE = 32;
    uint8 private constant COLORS_COUNT = 64;
    uint8 private constant BACKGROUND_COLORS_COUNT = 8;

    address public token;

    string[COLORS_COUNT] private colors = [
        // 0-7: Mortal stone palette
        "#1f1d1b",  // 0  mortal outline (dark stone)
        "#5e564e",  // 1  mortal mid body
        "#756a5d",  // 2  mortal face
        "#8a7c6c",  // 3  mortal cheek light
        "#5a5046",  // 4  mortal nose shadow
        "#3a342c",  // 5  mortal mouth
        "#837a6f",  // 6  mortal highlight
        "#b0a99e",  // 7  mortal seam
        // 8-19: Dark structural / neutrals / whites
        "#d4cebf",  // 8  mortal seam highlight
        "#0a1a25",  // 9  deepest blue-black
        "#1a1a1a",  // 10 pure dark
        "#1a2840",  // 11 dark navy
        "#2a3a5a",  // 12 mid navy (hoodie)
        "#3a3a3a",  // 13 mid grey (beanie)
        "#3a3a55",  // 14 cosmic grey-purple (god bg)
        "#5a5a5a",  // 15 lighter grey
        "#6c7088",  // 16 mortal class banner
        "#8a8a8a",  // 17 grey accent
        "#cccccc",  // 18 light grey (cigarette filter)
        "#ffffff",  // 19 pure white
        // 20-24: Hero coral pinks
        "#5a1838",  // 20 hero outline
        "#8a3050",  // 21 hero mouth shadow
        "#ee6c8c",  // 22 hero coral
        "#f5a0b0",  // 23 hero light coral
        "#ffc8d0",  // 24 hero highlight
        // 25-32: Demigod teal/greens
        "#143838",  // 25 demigod outline
        "#1a4848",  // 26 demigod mid outline
        "#3aa890",  // 27 demigod base
        "#5cc4a8",  // 28 demigod cheek
        "#6cd8b8",  // 29 demigod highlight
        "#88e0c8",  // 30 demigod accent
        "#9af0d0",  // 31 demigod light
        "#d0fff0",  // 32 demigod brightest
        // 33-34: Cyans / mage robe blues
        "#5cc4ff",  // 33 cyan (god astronaut collar)
        "#80c8ff",  // 34 light cyan (mage detail)
        // 35-41: Purples (god body, wizard hat)
        "#3a1a4a",  // 35 god outline / wizard hat dark
        "#5a2a6a",  // 36 wizard hat mid
        "#c850c0",  // 37 god class banner
        "#c8a0d8",  // 38 light purple
        "#d0a8e0",  // 39 lighter purple
        "#e0d0ff",  // 40 demigod bg / lavender
        "#f5e0ff",  // 41 god body
        // 42-47: Browns (mortal beard, hero jacket, titan body)
        "#3a1a08",  // 42 darkest brown (cowboy hat dark)
        "#3a1a25",  // 43 dark mauve (cigarette tip)
        "#4a3818",  // 44 dark olive-brown
        "#5a3010",  // 45 jacket dark brown
        "#6e3a18",  // 46 cowboy hat outline
        "#7a3a18",  // 47 cigar mid
        // 48-53: Golds (titan body, halo)
        "#2a2218",  // 48 titan outline
        "#8a6a30",  // 49 titan mid
        "#b08540",  // 50 titan face
        "#d4a64a",  // 51 titan class banner / monocle frame
        "#f0d070",  // 52 titan accent gold
        "#ffd070",  // 53 god lollipop yellow
        // 54-58: Light yellows
        "#fff088",  // 54 titan bg / god halo
        "#fff0b0",  // 55 light cream
        "#fff5d0",  // 56 lightest cream
        "#a06438",  // 57 jacket mid brown
        "#b91c1c",  // 58 (carryover, kept for compat)
        // 59-63: Reds / oranges / accents
        "#ee2050",  // 59 red pendant / accent
        "#ff5050",  // 60 bright red
        "#ff8020",  // 61 cigarette glow
        "#ff80b8",  // 62 god lollipop pink
        "#ff9c5a"   // 63 hero bg tangerine
    ];

    string[BACKGROUND_COLORS_COUNT] private backgroundColors = [
        "#0d1018",
        "#171b24",
        "#1b2632",
        "#211d2e",
        "#20261d",
        "#2a2218",
        "#101f24",
        "#24151d"
    ];

    mapping(uint256 => Rect[]) internal _mouth;        // (was: _accessories)
    mapping(uint256 => Rect[]) internal _skin;         // (was: _body)
    mapping(uint256 => Rect[]) internal _eyes;
    mapping(uint256 => Rect[]) internal _crown;        // (was: _hair)
    mapping(uint256 => Rect[]) internal _ear;          // (was: _horn)
    mapping(uint256 => Rect[]) internal _face;         // (was: _legsFront)
    mapping(uint256 => Rect[]) internal _tool;         // (was: _tail)
    mapping(uint256 => Rect[]) internal _cloth;        // (was: _wings)
    mapping(uint256 => Rect[]) internal _classOverlay;

    uint256 public mouthCount;
    uint256 public skinCount;
    uint256 public eyesCount;
    uint256 public crownCount;
    uint256 public earCount;
    uint256 public faceCount;
    uint256 public toolCount;
    uint256 public clothCount;
    uint256 public classOverlayCount;

    constructor(address owner_) OwnableBase(owner_) {}

    function setToken(address token_) public virtual onlyOwner {
        token = token_;
    }

    function setMouth(FileData[] memory rects) public onlyOwner {
        mouthCount += InputDataLibrary.set(_mouth, rects);
    }

    function setSkin(FileData[] memory rects) public onlyOwner {
        skinCount += InputDataLibrary.set(_skin, rects);
    }

    function setEyes(FileData[] memory rects) public onlyOwner {
        eyesCount += InputDataLibrary.set(_eyes, rects);
    }

    function setCrown(FileData[] memory rects) public onlyOwner {
        crownCount += InputDataLibrary.set(_crown, rects);
    }

    function setEar(FileData[] memory rects) public onlyOwner {
        earCount += InputDataLibrary.set(_ear, rects);
    }

    function setFace(FileData[] memory rects) public onlyOwner {
        faceCount += InputDataLibrary.set(_face, rects);
    }

    function setTool(FileData[] memory rects) public onlyOwner {
        toolCount += InputDataLibrary.set(_tool, rects);
    }

    function setCloth(FileData[] memory rects) public onlyOwner {
        clothCount += InputDataLibrary.set(_cloth, rects);
    }

    function setClassOverlay(FileData[] memory rects) public onlyOwner {
        classOverlayCount += InputDataLibrary.set(_classOverlay, rects);
    }

    function getSeedData(
        uint256 seed
    ) public pure returns (UpegMetadata memory) {
        return UpegMetadataLibrary.decode(seed);
    }

    function generate(uint256 seed) public view returns (string memory) {
        return generate(seed, 0);
    }

    function generate(
        uint256 seed,
        uint8 classIdx
    ) public view returns (string memory) {
        return generateSvg(UpegMetadataLibrary.decode(seed), classIdx);
    }

    function generateSvg(
        UpegMetadata memory seedData
    ) public view returns (string memory) {
        return generateSvg(seedData, 0);
    }

    function generateSvg(
        UpegMetadata memory seedData,
        uint8 classIdx
    ) public view returns (string memory) {
        string memory svg = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32' shape-rendering='crispEdges'>",
            Rect({
                x: 0,
                y: 0,
                width: SVG_SIZE,
                height: SVG_SIZE,
                colorIdx: 0
            }).toSvg(backgroundColors[seedData.background % BACKGROUND_COLORS_COUNT])
        );

        if (seedData.skin > 0) svg = string.concat(svg, _render(_skin[seedData.skin], seedData.skinColor));
        if (seedData.face > 0) svg = string.concat(svg, _render(_face[seedData.face], seedData.skinColor));
        if (seedData.eyes > 0) svg = string.concat(svg, _render(_eyes[seedData.eyes], seedData.eyesColor));
        if (seedData.mouth > 0) svg = string.concat(svg, _render(_mouth[seedData.mouth], seedData.mouthColor));
        if (seedData.crown > 0) svg = string.concat(svg, _render(_crown[seedData.crown], seedData.crownColor));
        if (seedData.ear > 0) svg = string.concat(svg, _render(_ear[seedData.ear], seedData.earColor));
        if (seedData.cloth > 0) svg = string.concat(svg, _render(_cloth[seedData.cloth], seedData.skinColor));
        if (seedData.tool > 0) svg = string.concat(svg, _render(_tool[seedData.tool], seedData.toolColor));
        if (classIdx > 0) svg = string.concat(svg, _render(_classOverlay[classIdx], classIdx));

        return string.concat(svg, "</svg>");
    }

    function renderUpeg(uint256 upegId) external view returns (string memory) {
        IUoreRenderView uore = IUoreRenderView(token);
        uint256 seed = uore.upegSeedOf(upegId);
        uint8 classIdx = uore.getClass(upegId);
        return generate(seed, classIdx);
    }

    function getImageParams() external view override returns (ImageParams memory) {
        return
            ImageParams({
                colorsCount: COLORS_COUNT,
                backgroundColorsCount: BACKGROUND_COLORS_COUNT,
                mouthCount: mouthCount,
                skinCount: skinCount,
                eyesCount: eyesCount,
                crownCount: crownCount,
                earCount: earCount,
                faceCount: faceCount,
                reserved1Count: 0,        // unused slot
                toolCount: toolCount,
                reserved2Count: 0,        // unused slot
                clothCount: clothCount
            });
    }

    function _render(
        Rect[] storage rects,
        uint8 fallbackColorIdx
    ) internal view returns (string memory out) {
        for (uint256 i; i < rects.length; ++i) {
            uint8 colorIdx = rects[i].colorIdx == 0
                ? fallbackColorIdx
                : rects[i].colorIdx;
            out = string.concat(out, rects[i].toSvg(colors[colorIdx % COLORS_COUNT]));
        }
    }
}
