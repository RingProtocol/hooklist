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

import "erc721a/contracts/ERC721A.sol";

interface IFactorySync {
    function syncCreator(address tickerToken, address newCreator) external;
}

/// @title Tickr Owner (V4)
/// @notice One NFT per ticker token launched via the V4 Factory. The NFT holder is
///         the on-chain owner of the ticker — fees route to the holder, and transferring
///         the NFT transfers the creator role atomically (factory.syncCreator hook).
contract TickrOwnerV4 is ERC721A {
    address public governor;
    address public pendingGovernor;
    address public factory;
    string private _baseTokenURI;

    /// @notice tokenId → ticker ERC20 token contract address
    mapping(uint256 => address) public tickerTokenOf;
    /// @notice ticker ERC20 token contract address → tokenId (0 means not minted)
    mapping(address => uint256) public tokenIdOfTicker;

    event FactorySet(address indexed factory);
    event TickerMinted(uint256 indexed tokenId, address indexed tickerToken, address indexed creator);
    event GovernorTransferStarted(address indexed currentGovernor, address indexed pendingGovernor);
    event GovernorTransferred(address indexed previousGovernor, address indexed newGovernor);
    event BaseURISet(string baseURI);

    modifier onlyGovernor() {
        require(msg.sender == governor, "Not governor");
        _;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "Not factory");
        _;
    }

    constructor(address _governor) ERC721A("Tickr Owner", "TICKR") {
        require(_governor != address(0), "Zero governor");
        governor = _governor;
        emit GovernorTransferred(address(0), _governor);
    }

    /// @dev Token IDs start at 1 so `tokenIdOfTicker == 0` reliably means "not minted".
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    /// @notice One-time bind. Factory is deployed after this contract; once set, immutable
    ///         (security parity with launchHook.setFactory).
    function setFactory(address _factory) external onlyGovernor {
        require(factory == address(0), "Already set");
        require(_factory != address(0), "Zero address");
        factory = _factory;
        emit FactorySet(_factory);
    }

    /// @notice Called by factory inside `deployCoin`. Mints exactly 1 NFT to the creator
    ///         and links it to the ticker token contract.
    function mintFor(address to, address _tickerToken)
        external
        onlyFactory
        returns (uint256 tokenId)
    {
        require(to != address(0), "Zero recipient");
        require(_tickerToken != address(0), "Zero ticker");
        require(tokenIdOfTicker[_tickerToken] == 0, "Already minted");

        tokenId = _nextTokenId();
        tickerTokenOf[tokenId] = _tickerToken;
        tokenIdOfTicker[_tickerToken] = tokenId;

        // _mint (not _safeMint) so contract-deployers without IERC721Receiver are not blocked.
        _mint(to, 1);
        emit TickerMinted(tokenId, _tickerToken, to);
    }

    /// @dev On any non-mint, non-burn transfer, notify factory so the on-chain creator
    ///      and fee routing follow the NFT.
    function _afterTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal override {
        super._afterTokenTransfers(from, to, startTokenId, quantity);
        if (from == address(0) || to == address(0)) return; // mint or burn

        for (uint256 i = 0; i < quantity; i++) {
            address tt = tickerTokenOf[startTokenId + i];
            if (tt != address(0)) {
                IFactorySync(factory).syncCreator(tt, to);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Metadata
    // ─────────────────────────────────────────────────────────────────────
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string calldata baseURI) external onlyGovernor {
        _baseTokenURI = baseURI;
        emit BaseURISet(baseURI);
    }

    // ─────────────────────────────────────────────────────────────────────
    // 2-step governor transfer
    // ─────────────────────────────────────────────────────────────────────
    function transferGovernor(address newGovernor) external onlyGovernor {
        require(newGovernor != address(0), "Zero address");
        pendingGovernor = newGovernor;
        emit GovernorTransferStarted(governor, newGovernor);
    }

    function acceptGovernor() external {
        require(msg.sender == pendingGovernor, "Not pending governor");
        address oldGovernor = governor;
        governor = msg.sender;
        delete pendingGovernor;
        emit GovernorTransferred(oldGovernor, msg.sender);
    }
}
