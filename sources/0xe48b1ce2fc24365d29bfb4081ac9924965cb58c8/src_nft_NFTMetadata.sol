// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NFTBase} from "./NFTBase.sol";

abstract contract NFTMetadata is NFTBase {
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        ownerOf(tokenId); // reverts TokenDoesNotExist for unminted IDs
        if (tokenId >= SINGULARITY_ID_OFFSET) {
            return _singularityTokenURI(tokenId);
        }
        bytes memory json = abi.encodePacked(
            '{"name":"Vortex #', _toString(tokenId),
            '","description":"Vortex of SPIN. Minted by staking 13,000 SPIN tokens for 7 days.",',
            '"image":"data:image/svg+xml;base64,', _base64(_generateSVG(tokenId)), '",',
            '"attributes":[',
            '{"trait_type":"Token ID","value":', _toString(tokenId), '},',
            '{"trait_type":"Minter","value":"', _toHexString(mintRecords[tokenId].minter), '"},',
            '{"trait_type":"Mint Requirement","value":"13,000 SPIN"},',
            '{"trait_type":"Lock Duration","value":"7 days"}',
            ']}'
        );

        return string(abi.encodePacked("data:application/json;base64,", _base64(json)));
    }

    function _generateSVG(uint256 tokenId) internal pure returns (bytes memory) {
        bytes memory hexChars = "0123456789abcdef";
        uint256 seed = uint256(keccak256(abi.encode(tokenId)));
        string memory bg = _colorHex(hexChars, seed);
        string memory fg = _colorHex(hexChars, seed >> 32);

        // Pixel letter "V" centered (5x3, 60px/px, padded 50px sides, 110px top/bottom)
        uint256 X0 = 50; uint256 Y0 = 110; uint256 P = 60;
        return abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" shape-rendering="crispEdges">',
            '<rect width="400" height="400" fill="', bg, '"/>',
            '<rect x="',_toString(X0),'" y="',_toString(Y0),'" width="',_toString(P),'" height="',_toString(P),'" fill="',fg,'"/>',
            '<rect x="',_toString(X0+4*P),'" y="',_toString(Y0),'" width="',_toString(P),'" height="',_toString(P),'" fill="',fg,'"/>',
            '<rect x="',_toString(X0+P),'" y="',_toString(Y0+P),'" width="',_toString(P),'" height="',_toString(P),'" fill="',fg,'"/>',
            '<rect x="',_toString(X0+3*P),'" y="',_toString(Y0+P),'" width="',_toString(P),'" height="',_toString(P),'" fill="',fg,'"/>',
            '<rect x="',_toString(X0+2*P),'" y="',_toString(Y0+2*P),'" width="',_toString(P),'" height="',_toString(P),'" fill="',fg,'"/>',
            '</svg>'
        );
    }

    function _colorHex(bytes memory hexChars, uint256 seed) internal pure returns (string memory) {
        bytes memory c = new bytes(7);
        c[0] = "#";
        for (uint8 i = 0; i < 6; i++) {
            c[i + 1] = hexChars[(seed >> (i * 4)) & 0xf];
        }
        return string(c);
    }

    function _base64(bytes memory data) internal pure returns (string memory) {
        bytes memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        uint256 fullGroups = data.length / 3;
        uint256 remainder = data.length % 3;
        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        bytes memory result = new bytes(encodedLen);

        uint256 resultIdx;
        for (uint256 i = 0; i < fullGroups; i++) {
            uint256 idx = i * 3;
            uint256 chunk = (uint256(uint8(data[idx])) << 16) | (uint256(uint8(data[idx + 1])) << 8) | uint256(uint8(data[idx + 2]));
            result[resultIdx++] = table[(chunk >> 18) & 0x3f];
            result[resultIdx++] = table[(chunk >> 12) & 0x3f];
            result[resultIdx++] = table[(chunk >> 6) & 0x3f];
            result[resultIdx++] = table[chunk & 0x3f];
        }

        if (remainder == 1) {
            uint256 idx = fullGroups * 3;
            uint256 chunk = uint256(uint8(data[idx])) << 16;
            result[resultIdx++] = table[(chunk >> 18) & 0x3f];
            result[resultIdx++] = table[(chunk >> 12) & 0x3f];
            result[resultIdx++] = "=";
            result[resultIdx++] = "=";
        } else if (remainder == 2) {
            uint256 idx = fullGroups * 3;
            uint256 chunk = (uint256(uint8(data[idx])) << 16) | (uint256(uint8(data[idx + 1])) << 8);
            result[resultIdx++] = table[(chunk >> 18) & 0x3f];
            result[resultIdx++] = table[(chunk >> 12) & 0x3f];
            result[resultIdx++] = table[(chunk >> 6) & 0x3f];
            result[resultIdx++] = "=";
        }

        return string(result);
    }

    function _singularityTokenURI(uint256 tokenId) internal view returns (string memory) {
        Rarity r = singularityRarity[tokenId];
        string memory rarityStr;
        if (r == Rarity.Common) rarityStr = "Common";
        else if (r == Rarity.Rare) rarityStr = "Rare";
        else if (r == Rarity.Epic) rarityStr = "Epic";
        else if (r == Rarity.Legendary) rarityStr = "Legendary";
        else rarityStr = "Mythic";

        bytes memory json = abi.encodePacked(
            '{"name":"Singularity #', _toString(tokenId - SINGULARITY_ID_OFFSET),
            '","description":"Singularity of SPIN. Forged from 13,000 SPIN and 2 Vortex of SPIN NFTs.",',
            '"image":"data:image/svg+xml;base64,', _base64(_generateSingularitySVG(tokenId, r)), '",',
            '"attributes":[',
            '{"trait_type":"Token ID","value":', _toString(tokenId), '},',
            '{"trait_type":"Rarity","value":"', rarityStr, '"},',
            '{"trait_type":"Type","value":"Singularity"}',
            ']}'
        );
        return string(abi.encodePacked("data:application/json;base64,", _base64(json)));
    }

    function _generateSingularitySVG(uint256 tokenId, Rarity rarity) internal pure returns (bytes memory) {
        // Rarity-specific color palettes (edge, middle, center)
        string memory c1; string memory c2; string memory c3;
        if (rarity == Rarity.Common)      { c1 = "#446688"; c2 = "#5588aa"; c3 = "#88bbdd"; }
        else if (rarity == Rarity.Rare)   { c1 = "#553388"; c2 = "#7744bb"; c3 = "#9966ee"; }
        else if (rarity == Rarity.Epic)   { c1 = "#664422"; c2 = "#996633"; c3 = "#ddaa44"; }
        else if (rarity == Rarity.Legendary) { c1 = "#883322"; c2 = "#cc5522"; c3 = "#ff8833"; }
        else /* Mythic */                 { c1 = "#881122"; c2 = "#dd2233"; c3 = "#ff4466"; }

        // Add per-token variation by shifting hues slightly
        uint256 seed = uint256(keccak256(abi.encode(tokenId, "sg")));
        if ((seed & 1) == 1) { string memory t = c1; c1 = c2; c2 = t; } // swap edge/mid

        // Pixel "S" centered (5x5, 60px/px). Higher rarity = extra pixels.
        uint256 X = 50; uint256 P = 60;
        // Core S: top bar, left-top, middle bar, right-bottom, bottom bar
        bytes memory s = abi.encodePacked(
            '<rect x="',_toString(X+P),'" y="',_toString(X),'" width="',_toString(3*P),'" height="',_toString(P),'" fill="',c3,'"/>',
            '<rect x="',_toString(X),'" y="',_toString(X+P),'" width="',_toString(P),'" height="',_toString(P),'" fill="',c3,'"/>',
            '<rect x="',_toString(X+P),'" y="',_toString(X+2*P),'" width="',_toString(3*P),'" height="',_toString(P),'" fill="',c2,'"/>',
            '<rect x="',_toString(X+4*P),'" y="',_toString(X+3*P),'" width="',_toString(P),'" height="',_toString(P),'" fill="',c3,'"/>',
            '<rect x="',_toString(X+P),'" y="',_toString(X+4*P),'" width="',_toString(3*P),'" height="',_toString(P),'" fill="',c3,'"/>'
        );
        // Rarity extras
        if (rarity >= Rarity.Epic)      s = abi.encodePacked(s, '<rect x="',_toString(X+4*P),'" y="',_toString(X+P),'" width="',_toString(P),'" height="',_toString(P),'" fill="',c3,'"/>');
        if (rarity >= Rarity.Legendary) s = abi.encodePacked(s, '<rect x="',_toString(X),'" y="',_toString(X+2*P),'" width="',_toString(P),'" height="',_toString(P),'" fill="',c3,'"/>');
        if (rarity >= Rarity.Mythic)    s = abi.encodePacked(s, '<rect x="',_toString(X+4*P),'" y="',_toString(X),'" width="',_toString(P),'" height="',_toString(P),'" fill="',c3,'"/>');

        return abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" shape-rendering="crispEdges">',
            '<rect width="400" height="400" fill="', c1, '"/>', s, '</svg>'
        );
    }
}
