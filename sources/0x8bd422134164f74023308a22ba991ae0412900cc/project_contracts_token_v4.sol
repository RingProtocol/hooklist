// SPDX-License-Identifier: MIT
//
//   ████████╗██╗ ██████╗██╗  ██╗██████╗
//   ╚══██╔══╝██║██╔════╝██║ ██╔╝██╔══██╗
//      ██║   ██║██║     █████╔╝ ██████╔╝
//      ██║   ██║██║     ██╔═██╗ ██╔══██╗
//      ██║   ██║╚██████╗██║  ██╗██║  ██║
//      ╚═╝   ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝
//
//   Website: https://tickr.xyz
//   Twitter: https://x.com/tickrxyz
//
pragma solidity >=0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20, ERC20Burnable {
    address public platform;
    address public creator;
    address private _owner;

    event FeesReceived(uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol,
        address _creator,
        address _platform
    ) ERC20(_name, _symbol) {
        platform = _platform;
        creator = _creator;
        _owner = address(0);

        _mint(_platform, 1_000_000_000 * 10 ** decimals());
    }

    // Etherscan/scanners report ownership as renounced. _owner is hardcoded
    // to zero in the constructor and is never reassignable.
    function owner() public view returns (address) {
        return _owner;
    }

    // Hook fee ETH lands here on every ETH→Token swap.
    receive() external payable {
        emit FeesReceived(msg.value);
    }

    // Only factory can pull accumulated fees. Factory then forwards to creator.
    function withdrawFees() external returns (uint256 balance) {
        require(msg.sender == platform, "Only factory");
        balance = address(this).balance;
        require(balance > 0, "No fees");
        (bool s, ) = payable(platform).call{value: balance}("");
        require(s, "Transfer failed");
    }

    function changeCreator(address newCreator) external {
        require(msg.sender == platform, "Only platform");
        creator = newCreator;
    }
}
