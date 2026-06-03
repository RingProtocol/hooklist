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

contract TokenRegistry {
    event SymbolRegistered(string indexed symbolHash, string symbol, address indexed factory);
    event FactoryAdded(address indexed factory);
    event FactoryRemoved(address indexed factory);
    event SymbolReserved(string indexed symbolHash, string symbol);
    event SymbolUnreserved(string indexed symbolHash, string symbol);
    event CharRuleChanged(bytes1 indexed char, bool allowed);
    event GovernorTransferStarted(address indexed currentGovernor, address indexed pendingGovernor);
    event GovernorTransferred(address indexed previousGovernor, address indexed newGovernor);

    address public governor;
    address public pendingGovernor;

    mapping(address => bool) public isFactory;
    mapping(string => bool) public symbolTaken;
    mapping(string => bool) public reservedSymbols;

    // Each bit i represents whether ASCII byte 0xi is allowed in symbols.
    uint256 public allowedCharMask;

    uint256 public constant MAX_SYMBOL_LENGTH = 32;

    modifier onlyGovernor() {
        require(msg.sender == governor, "Not governor");
        _;
    }

    modifier onlyFactory() {
        require(isFactory[msg.sender], "Not factory");
        _;
    }

    constructor() {
        governor = msg.sender;

        uint256 mask;
        for (uint8 i = 0x30; i <= 0x39; i++) mask |= (uint256(1) << i); // 0-9
        for (uint8 i = 0x41; i <= 0x5A; i++) mask |= (uint256(1) << i); // A-Z
        for (uint8 i = 0x61; i <= 0x7A; i++) mask |= (uint256(1) << i); // a-z
        allowedCharMask = mask;

        emit GovernorTransferred(address(0), msg.sender);
    }

    function registerSymbol(string calldata symbol) external onlyFactory {
        require(_isValidSymbol(symbol), "Invalid symbol");
        require(!symbolTaken[symbol], "Symbol taken");
        require(!reservedSymbols[symbol], "Symbol reserved");

        symbolTaken[symbol] = true;
        emit SymbolRegistered(symbol, symbol, msg.sender);
    }

    function isAvailable(string calldata symbol) external view returns (bool) {
        if (!_isValidSymbol(symbol)) return false;
        if (symbolTaken[symbol]) return false;
        if (reservedSymbols[symbol]) return false;
        return true;
    }

    function _isValidSymbol(string memory s) internal view returns (bool) {
        bytes memory b = bytes(s);
        uint256 len = b.length;
        if (len == 0 || len > MAX_SYMBOL_LENGTH) return false;

        uint256 mask = allowedCharMask;
        for (uint256 i = 0; i < len; i++) {
            if (mask & (uint256(1) << uint8(b[i])) == 0) return false;
        }
        return true;
    }

    function addFactory(address factory) external onlyGovernor {
        require(factory != address(0), "Zero address");
        require(!isFactory[factory], "Already added");
        isFactory[factory] = true;
        emit FactoryAdded(factory);
    }

    function removeFactory(address factory) external onlyGovernor {
        require(isFactory[factory], "Not a factory");
        isFactory[factory] = false;
        emit FactoryRemoved(factory);
    }

    function reserveSymbol(string calldata symbol) external onlyGovernor {
        require(!symbolTaken[symbol], "Already registered");
        require(!reservedSymbols[symbol], "Already reserved");
        reservedSymbols[symbol] = true;
        emit SymbolReserved(symbol, symbol);
    }

    function unreserveSymbol(string calldata symbol) external onlyGovernor {
        require(reservedSymbols[symbol], "Not reserved");
        reservedSymbols[symbol] = false;
        emit SymbolUnreserved(symbol, symbol);
    }

    function setCharAllowed(bytes1 char, bool allowed) external onlyGovernor {
        uint256 bit = uint256(1) << uint8(char);
        if (allowed) {
            allowedCharMask |= bit;
        } else {
            allowedCharMask &= ~bit;
        }
        emit CharRuleChanged(char, allowed);
    }

    function isCharAllowed(bytes1 char) external view returns (bool) {
        return allowedCharMask & (uint256(1) << uint8(char)) != 0;
    }

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
