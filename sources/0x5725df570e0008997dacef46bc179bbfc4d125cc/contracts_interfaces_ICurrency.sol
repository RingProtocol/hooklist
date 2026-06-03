// SPDX-License-Identifier: MIT
// Qian Exchange - https://qian.ag
pragma solidity ^0.8.24;

/// @notice Currency type for Uniswap V4
/// Wraps an address to represent a token or native ETH
type Currency is address;

/// @notice Currency library for V4
library CurrencyLibrary {
    /// @notice Wrap an address as Currency
    function wrap(address token) internal pure returns (Currency) {
        return Currency.wrap(token);
    }
    
    /// @notice Unwrap Currency to address
    function unwrap(Currency currency) internal pure returns (address) {
        return Currency.unwrap(currency);
    }
    
    /// @notice Native ETH currency
    function native() internal pure returns (Currency) {
        return Currency.wrap(address(0));
    }
    
    /// @notice Check if currency is native ETH
    function isNative(Currency currency) internal pure returns (bool) {
        return Currency.unwrap(currency) == address(0);
    }
}

