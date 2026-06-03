// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../upegs/Upeg.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {IStartableToken} from "./IStartableToken.sol";

/// @title UpegToken
/// @notice ERC20 token that syncs Upeg with balances, excluding the liquidity pool address.
/// - Mints Upegs on transfers from the pool
/// - Burns Upegs when sending to the pool or zero address
/// - Transfers Upegs 1:1 on user-to-user transfers
/// All operations use UNIT_PER_UPEG (tokens per Upeg) to avoid excessive minting.
contract UpegToken is Upeg, ERC20, Ownable, IStartableToken {
    error AddressCanNotReceiveUpeg();

    uint256 public constant UNIT_PER_UPEG = 1e18; // tokens per Upeg
    uint256 public constant INITIAL_SUPPLY = 10_000e18; // initial supply to owner

    // max buy configuration
    uint256 constant MAX_BUY_PRECISION = 100000;
    uint256 constant _startMaxBuyCount =
        (INITIAL_SUPPLY * 250) / MAX_BUY_PRECISION; // 0.25% of initial supply
    uint256 constant _addMaxBuyPercentPerSec = 3; // add 0.003%/second

    address immutable _notMintableAccount; // deployer cannot mint Upegs to prevent abuse
    uint256 _startTime;
    address public hook;

    // settings
    address public pool; // excluded address (liquidity pool)

    // constructors
    constructor(address owner_) {
        _initializeOwner(owner_);
        _mint(owner_, INITIAL_SUPPLY);
        _notMintableAccount = owner_;
    }

    modifier canReceiveUpegs(address addr) {
        if (!_canReceiveUpegs(addr)) revert AddressCanNotReceiveUpeg();
        _;
    }

    /// @notice Ensures the call is made only by the Uniswap v4 hook.
    modifier onlyHook() {
        require(msg.sender == hook, "only for hook");
        _;
    }

    // Name/symbol are static like in TestToken.
    function name() public pure override returns (string memory) {
        return "Sync Token";
    }

    function symbol() public pure override returns (string memory) {
        return "SYNC";
    }

    /// @notice Sets the liquidity pool address and enables buying.
    function start(address newPool) external onlyHook {
        pool = newPool;
        _startTime = block.timestamp;
    }

    function isStarted() public view returns (bool) {
        return pool != address(0);
    }

    function maxBuy() public view returns (uint256) {
        if (!isStarted()) return 0;
        uint256 count = _startMaxBuyCount +
            (INITIAL_SUPPLY *
                (block.timestamp - _startTime) *
                _addMaxBuyPercentPerSec) /
            MAX_BUY_PRECISION;
        if (count > INITIAL_SUPPLY) count = INITIAL_SUPPLY;
        return count;
    }

    /// @notice Sets the Uniswap v4 hook address.
    function setHook(address newHook) external onlyOwner {
        hook = newHook;
    }

    /// @dev Sets the image parameters provider.
    /// @param imageParamsProvider Contract implementing IImageParams
    function setImageParamsProvider(
        address imageParamsProvider
    ) public onlyOwner {
        _setImageParamsProvider(imageParamsProvider);
    }

    /// @dev Sets the random seed provider.
    /// @param randomSeedProvider Contract implementing IRandomSeed
    function setRandomSeedProvider(
        address randomSeedProvider
    ) public onlyOwner {
        _setRandomSeedProvider(randomSeedProvider);
    }

    // methods
    /// @dev Reacts to token transfers and syncs Upeg.
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._afterTokenTransfer(from, to, amount);
        if (pool == address(0)) return;
        _onTokenTransfer(from, to, amount, createRandom());
    }

    // ----- internals -----
    function _onTokenTransfer(
        address from,
        address to,
        uint256 amount,
        Random memory random
    ) internal {
        // If pool is not set yet, do not sync (e.g. during initial mint).
        if (pool == address(0)) return;

        // pool -> user: mint Upegs
        if (from == pool && to != address(0)) {
            // deployer will not have hooks to prevent the abuse
            if (_notMintableAccount == to) return;
            require(isStarted(), "not started");
            // max buy limit (grows over time)
            require(amount <= maxBuy(), "buy limit");
            _mintUpegs(to, amount / UNIT_PER_UPEG, random);
            return;
        }

        // determine how many Upegs to remove from sender
        uint256 from_max_allowed = balanceOf(from) / UNIT_PER_UPEG;
        uint256 from_count = this.OwnerUpegsCount(from);
        uint256 from_remove_cnount = from_count > from_max_allowed
            ? from_count - from_max_allowed
            : 0;

        // determine how many Upegs the receiver can accept
        uint256 to_max_allowed = balanceOf(to) / UNIT_PER_UPEG;
        uint256 to_count = this.OwnerUpegsCount(to);
        uint256 to_receive_allowed = to_count < to_max_allowed
            ? to_max_allowed - to_count
            : 0;

        // if no Upegs to move, do nothing
        if (from_remove_cnount == 0) return;

        // if receiver cannot receive Upegs
        if (!_canReceiveUpegs(to)) {
            to_receive_allowed = 0;
        }

        // user -> user: move Upegs
        uint256 move_qty = from_remove_cnount < to_receive_allowed
            ? from_remove_cnount
            : to_receive_allowed;
        if (move_qty > 0) _moveUpegs(from, to, move_qty);

        // burn remaining Upegs from sender
        _burnUpegs(from, from_remove_cnount - move_qty);
    }

    function _mintUpegs(
        address user,
        uint256 qty,
        Random memory random
    ) internal {
        for (uint256 i = 0; i < qty; i++) {
            _mintUpeg(user, random);
        }
    }

    function _burnUpegs(address user, uint256 qty) internal {
        for (uint256 i = 0; i < qty; i++) {
            uint count = this.OwnerUpegsCount(user);
            if (count == 0) break; // nothing to burn
            uint lastIdx = count - 1;
            uint upegId = this.OwnerUpeg(user, lastIdx).id;
            _burnUpeg(user, upegId);
        }
    }

    function _moveUpegs(
        address from,
        address to,
        uint256 qty
    ) internal canReceiveUpegs(to) {
        for (uint256 i = 0; i < qty; i++) {
            uint count = this.OwnerUpegsCount(from);
            if (count == 0) break; // nothing to move
            uint lastIdx = count - 1;
            uint upegId = this.OwnerUpeg(from, lastIdx).id;
            _transferUpeg(from, to, upegId);
        }
    }

    function _canReceiveUpegs(address addr) internal view returns (bool) {
        return addr != pool && addr != address(0);
    }

    function _afterUpegTransferred(
        address from,
        address to,
        uint upegId
    ) internal override {
        _transfer(from, to, UNIT_PER_UPEG);
    }

    function _afterUpegsListTransferred(
        address from,
        address to,
        uint[] calldata upegIds
    ) internal override {
        _transfer(from, to, UNIT_PER_UPEG * upegIds.length);
    }
}
