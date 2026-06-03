// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

type Currency is address;

library CurrencyLibrary {
  Currency public constant NATIVE = Currency.wrap(address(0));

  function isNative(Currency currency) internal pure returns (bool) {
    return Currency.unwrap(currency) == address(0);
  }

  function unwrap(Currency currency) internal pure returns (address) {
    return Currency.unwrap(currency);
  }

  function wrap(address addr) internal pure returns (Currency) {
    return Currency.wrap(addr);
  }
}
