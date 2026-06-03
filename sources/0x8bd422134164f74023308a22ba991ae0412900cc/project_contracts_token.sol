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

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function factory() external view returns (address);
    function WETH9() external view returns (address);

    function positions(uint256 tokenId) external view returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external returns (address pool);

    function mint(MintParams calldata params) external returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function collect(CollectParams calldata params) external payable returns (
        uint256 amount0,
        uint256 amount1
    );

    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function ownerOf(uint256 tokenId) external view returns (address);
}


contract Token is ERC20, ERC20Burnable {
    address public platform;
    address public creator;

    address public constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor(
        string memory _name,
        string memory _symbol,
        address _creator,
        address _platform
    ) ERC20(_name, _symbol) {
        platform = _platform;
        creator = _creator;

        _mint(_platform, 1_000_000_000 * 10 ** decimals());
    }

    function getTokenPair() public view returns (address, address, address) {
        address find_factory = INonfungiblePositionManager(POSITION_MANAGER).factory();
        address find_pool = IUniswapV3Factory(find_factory).getPool(address(this), WETH, 10000);
        return (find_pool, address(this), find_factory);
    }

    function changeCreator(address newCreator) external {
        require(msg.sender == platform, "Only platform can change creator");
        creator = newCreator;
    }
}
