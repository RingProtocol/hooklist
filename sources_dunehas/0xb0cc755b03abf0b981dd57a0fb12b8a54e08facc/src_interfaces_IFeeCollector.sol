// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/*//////////////////////////////////////////////////////////////
                              lo0p
                    web · https://lo0p.io
                    x   · https://x.com/lo0pio
                    tg  · https://t.me/lo0pio
//////////////////////////////////////////////////////////////*/

interface IFeeCollector {
    function withdraw(address payable to, uint256 amount) external;
    function transferOwnership(address newOwner) external;
    function owner() external view returns (address);
}
