// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IStartableToken {
    function start() external;
    function started() external view returns (bool);
}
