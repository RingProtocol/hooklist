// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UD60x18, ud, exp, ln} from "prb-math/UD60x18.sol";

/// @title SpinCurve
/// @notice Bonding-curve math for SPIN token.
/// @dev    Forward:   totalMinted(eth) = K * (1 - e^{-eth / S})
///         Inverse:   eth from burn uses ln ratio form in `burnFor`.
library SpinCurve {
    uint256 internal constant K_SUPPLY = 3**21 * 1e18;
    uint256 internal constant S = 800e18;
    uint256 internal constant MAX_EXP_X = 50e18;

    error SellExceedsSupply();
    error InverseDomainError();

    function totalMinted(uint256 eth) internal pure returns (uint256) {
        if (eth == 0) return 0;
        UD60x18 sUd = ud(S);
        UD60x18 e = ud(eth);
        UD60x18 x = _div(e, sUd);
        if (x.unwrap() >= MAX_EXP_X) return K_SUPPLY;
        UD60x18 expPos = exp(x);
        UD60x18 invExp = _div(ud(1e18), expPos);
        UD60x18 oneMinus = _sub(ud(1e18), invExp);
        return _mul(ud(K_SUPPLY), oneMinus).unwrap();
    }

    function mintFor(uint256 ethBefore, uint256 eth) internal pure returns (uint256) {
        if (eth == 0) return 0;
        uint256 a = totalMinted(ethBefore);
        uint256 b = totalMinted(ethBefore + eth);
        return b > a ? b - a : 0;
    }

    function marginalPrice(uint256 eth) internal pure returns (uint256) {
        UD60x18 sUd = ud(S);
        UD60x18 e = ud(eth);
        UD60x18 x = _div(e, sUd);
        UD60x18 expPos = x.unwrap() >= MAX_EXP_X ? exp(ud(MAX_EXP_X)) : exp(x);
        UD60x18 num = _mul(sUd, expPos);
        return _div(num, ud(K_SUPPLY)).unwrap();
    }

    function burnFor(uint256 currentTotal, uint256 spinIn) internal pure returns (uint256) {
        if (spinIn == 0) return 0;
        if (spinIn > currentTotal) revert SellExceedsSupply();
        uint256 k = K_SUPPLY;
        uint256 denomU = k - currentTotal;
        if (denomU == 0) revert InverseDomainError();
        uint256 numU = denomU + spinIn;
        UD60x18 ratio = _div(ud(numU), ud(denomU));
        UD60x18 lnR = ln(ratio);
        return _mul(ud(S), lnR).unwrap();
    }

    function ethAt(uint256 currentTotal) internal pure returns (uint256) {
        if (currentTotal == 0) return 0;
        uint256 k = K_SUPPLY;
        if (currentTotal >= k) revert InverseDomainError();
        UD60x18 ratio = _div(ud(k), ud(k - currentTotal));
        UD60x18 lnR = ln(ratio);
        return _mul(ud(S), lnR).unwrap();
    }

    function _add(UD60x18 a, UD60x18 b) private pure returns (UD60x18) {
        return UD60x18.wrap(a.unwrap() + b.unwrap());
    }

    function _sub(UD60x18 a, UD60x18 b) private pure returns (UD60x18) {
        return UD60x18.wrap(a.unwrap() - b.unwrap());
    }

    function _mul(UD60x18 a, UD60x18 b) private pure returns (UD60x18) {
        return UD60x18.wrap((a.unwrap() * b.unwrap()) / 1e18);
    }

    function _div(UD60x18 a, UD60x18 b) private pure returns (UD60x18) {
        return UD60x18.wrap((a.unwrap() * 1e18) / b.unwrap());
    }
}
