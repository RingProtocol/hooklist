// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function allowance(address, address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/// @title Halo token — minimal ERC20 paired with the V4 phase-tax hook
/// @notice Tax / recoil / apex logic lives in HaloHook. The token has no
/// transfer hooks, no fees, no pause — pure ERC20 with two one-shot admin
/// actions: anointHook (wires the hook) and renounce (zeros the origin slot).
contract Halo is IERC20 {
    string  public constant name = "halo";
    string  public constant symbol = "halo";
    uint8   public constant decimals = 18;
    uint256 private constant _totalSupply = 1_000_000_000 * 10**18;

    /// Required low-14-bits of the V4 hook address. Mirrors
    /// HaloHook.REQUIRED_HOOK_BITS = 0x20CC (BEFORE_INITIALIZE | BEFORE_SWAP
    /// | AFTER_SWAP | BEFORE_SWAP_RETURNS_DELTA | AFTER_SWAP_RETURNS_DELTA).
    /// `anointHook` rejects any address whose lower bits don't match.
    uint256 private constant REQUIRED_HOOK_BITS = 0x20CC;

    address public hook;
    address public origin;

    mapping(address => uint256) private _bal;
    mapping(address => mapping(address => uint256)) private _allow;

    error AlreadyAnointed();
    error NoHook();
    error BadBits();
    error NotOrigin();
    error ZeroAddress();
    error ExceedsBalance();
    error ExceedsAllowance();

    event Anointed(address indexed hook);
    event Renounced();

    /// @param _origin The EOA that signs the deploy tx and gets the one-shot
    /// `anointHook` + `renounce` rights plus the full 1B supply. Required
    /// because CREATE2 deployment via the factory makes `msg.sender` the
    /// factory, not the EOA. The constructor enforces `_origin == tx.origin`
    /// so the origin slot can never be set to the factory, a contract, or
    /// anyone other than the EOA that signed the originating tx.
    constructor(address _origin) {
        if (_origin == address(0)) revert ZeroAddress();
        if (_origin != tx.origin) revert NotOrigin();
        origin = _origin;
        _bal[_origin] = _totalSupply;
        emit Transfer(address(0), _origin, _totalSupply);
    }

    /// @notice One-shot: wire the V4 hook into the token. Required hook bits
    /// must match (defence-in-depth — deploy script is the real gate).
    function anointHook(address _hook) external {
        if (msg.sender != origin) revert NotOrigin();
        if (hook != address(0)) revert AlreadyAnointed();
        if (_hook == address(0)) revert ZeroAddress();
        if (uint160(_hook) & 0x3FFF != REQUIRED_HOOK_BITS) revert BadBits();
        hook = _hook;
        emit Anointed(_hook);
    }

    /// @dev Infinite-approval optimization: when allowance is `type(uint256).max`,
    /// `transferFrom` does NOT decrement it. Saves an SSTORE per transfer.

    /// @notice Zero out the origin slot. Callable only after `anointHook` so
    /// the hook is permanently locked first. After this, no further admin
    /// actions remain on the token (no mint, no pause, no second anointHook).
    function renounce() external {
        if (msg.sender != origin) revert NotOrigin();
        if (hook == address(0)) revert NoHook();
        origin = address(0);
        emit Renounced();
    }

    function totalSupply() external pure returns (uint256) { return _totalSupply; }
    function balanceOf(address a) external view returns (uint256) { return _bal[a]; }
    function allowance(address o, address s) external view returns (uint256) { return _allow[o][s]; }

    function approve(address s, uint256 a) external returns (bool) {
        _allow[msg.sender][s] = a;
        emit Approval(msg.sender, s, a);
        return true;
    }

    function transfer(address to, uint256 amt) external returns (bool) {
        _transfer(msg.sender, to, amt);
        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        uint256 x = _allow[from][msg.sender];
        if (x != type(uint256).max) {
            if (x < amt) revert ExceedsAllowance();
            _allow[from][msg.sender] = x - amt;
        }
        _transfer(from, to, amt);
        return true;
    }

    function _transfer(address from, address to, uint256 amt) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        uint256 fromBal = _bal[from];
        if (fromBal < amt) revert ExceedsBalance();
        unchecked {
            _bal[from] = fromBal - amt;
            _bal[to] += amt;
        }
        emit Transfer(from, to, amt);
    }
}
