// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FullMath} from "v4-core/libraries/FullMath.sol";

/// @title WeiCurve
/// @notice Pure functions for the WEI bonding curve.
///
///         M(R) = K · R / (R + T)
///         p(R) = (R + T)² / (K · T)
///         R(M) = M · T / (K - M)
///
///         Closed forms used here:
///           mintFor(R, dE) = M(R+dE) - M(R) = K · dE · T / ((R+T) · (R+dE+T))
///           burnFor(q, b)  = R(q) - R(q-b) = T · b · K / ((K-q) · (K-q+b))
///
///         All inputs are 1e18-scaled. K and T are baked in as constants so the
///         library is auditable in isolation.
library WeiCurve {
    /// @notice Asymptotic supply cap (1B WEI, 18 decimals).
    uint256 internal constant K = 1_000_000_000e18;

    /// @notice Curve elasticity / EIP-1559 base-fee target (155.9 ETH).
    uint256 internal constant T = 155_900_000_000_000_000_000;

    /// @notice Reverts when burnFor is asked to retract more than the curve has issued.
    error BurnExceedsCurve();

    /// @notice Forward curve: WEI minted when ETH reserve grows by `dE` from `R`.
    /// @param  R  Current cumulative ETH reserve (1e18-scaled).
    /// @param  dE Additional ETH to push into the curve (1e18-scaled).
    /// @return    The amount of fair-curve WEI emitted (1e18-scaled).
    /// @dev   `mintFor(R, dE) = K * dE * T / ((R+T) * (R+dE+T))`. Numerator can
    ///        reach ~1e66 (well within uint512 mulDiv); we split as two mulDiv
    ///        calls to keep the intermediates inside uint256 even at the upper
    ///        end (R≈99T, dE near typed max).
    function mintFor(uint256 R, uint256 dE) internal pure returns (uint256) {
        if (dE == 0) return 0;

        uint256 a = R + T;          // R+T   ≤ 100T  ≈ 1.56e22
        uint256 b = R + dE + T;     // R+dE+T

        // step 1: K * dE / a            (overflow-safe, mulDiv)
        // step 2: result * T / b
        uint256 step = FullMath.mulDiv(K, dE, a);
        return FullMath.mulDiv(step, T, b);
    }

    /// @notice Inverse curve: ETH owed when retracting `b` WEI from fair supply `q`.
    /// @param  q  Fair-curve cumulative supply before the burn (1e18-scaled, ≤ K).
    /// @param  b  WEI to remove from the curve in fair units (1e18-scaled, ≤ q).
    /// @return    ETH refund (1e18-scaled).
    /// @dev   `burnFor(q, b) = T * b * K / ((K-q) * (K-q+b))`. With the
    ///        selfDeprecation cap at 99% K, K-q ≥ 0.01·K = 1e25, so denominators
    ///        stay safely above 0.
    function burnFor(uint256 q, uint256 b) internal pure returns (uint256) {
        if (b == 0) return 0;
        if (b > q) revert BurnExceedsCurve();

        uint256 d1 = K - q;         // K-q
        uint256 d2 = d1 + b;        // K-q+b  (= K - (q - b))

        // step 1: T * b / d1
        // step 2: result * K / d2
        uint256 step = FullMath.mulDiv(T, b, d1);
        return FullMath.mulDiv(step, K, d2);
    }

    /// @notice Marginal price at reserve `R` in 1e18 ETH per 1e18 WEI.
    /// @dev   `p(R) = (R+T)² / (K·T)`. View-only helper for tests and off-chain
    ///        quoting; not used in mint/burn routing.
    function priceAt(uint256 R) internal pure returns (uint256) {
        uint256 sum = R + T;
        // (R+T)² / (K·T)  →  ((R+T) * (R+T)) / (K * T)
        return FullMath.mulDiv(sum, sum, FullMath.mulDiv(K, T, 1e18)) ;
    }

    /// @notice Total WEI emitted at reserve `R`. View helper.
    function emittedAt(uint256 R) internal pure returns (uint256) {
        return FullMath.mulDiv(K, R, R + T);
    }
}
