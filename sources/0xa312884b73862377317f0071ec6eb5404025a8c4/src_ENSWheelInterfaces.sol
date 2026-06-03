// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IENSWheel {
    function addFees() external payable;
    function setMidSwap(bool value) external;
    function midSwap() external view returns (bool);
    function tradingEnabled() external view returns (bool);
}

interface IENSWheelFactory {
    function loadingLiquidity() external view returns (bool);
    function ENSWheelToCollection(address engine) external view returns (address);
    function owner() external view returns (address);
    function isWhitelistedBuyer(address buyer) external view returns (bool);
}

interface IENSWheelHook {
    function startFeeCountdown(address ENSWheel) external;
    function updateFeeAddress(address _feeAddress) external;
}

interface IERC721WithOwner is IERC721 {
    function owner() external view returns (address);
}

interface IPriceOracle {
    struct Price {
        uint256 base;
        uint256 premium;
    }
}

interface IETHRegistrarController {
    function rentPrice(string memory name, uint256 duration) external view returns (IPriceOracle.Price memory price);
    function renew(string calldata name, uint256 duration) external payable;
}
