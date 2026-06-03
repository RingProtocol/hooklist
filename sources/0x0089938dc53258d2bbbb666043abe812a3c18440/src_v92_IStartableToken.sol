// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStartableToken {
    function start(address newPool) external;
    function isStarted() external view returns (bool);
}
