// SPDX-License-Identifier: MIT
// BtcPegHook — direct fork of HenryPegHook93 (v9.3 design, recipient bug fixed).
// Identical logic, only contract name differs.

pragma solidity ^0.8.24;

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";

import {IRandomSeedProvider} from "../v92/RandomLib.sol";
import {IStartableToken} from "../v92/IStartableToken.sol";

interface IBtcPegMintable {
    function mintFragmentsFor(address to, uint256 qty) external;
}

contract BtcPegHook is IHooks, IRandomSeedProvider {
    IPoolManager public immutable poolManager;
    address public immutable owner;
    IStartableToken public token;
    uint256 _randomSeed;
    uint256 _randomCount;

    uint256 internal constant UNIT_PER_BPEG = 1e18;

    error NotPoolManager();
    error NotOwner();
    error InvalidHookData();

    modifier onlyPM() { if (msg.sender != address(poolManager)) revert NotPoolManager(); _; }
    modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }

    constructor(IPoolManager _pm, address _owner) {
        poolManager = _pm;
        owner = _owner;
        _randomSeed = block.timestamp;
    }

    function setToken(address tokenAddress) external onlyOwner {
        token = IStartableToken(tokenAddress);
    }

    function isTokenSetted() public view returns (bool) {
        return address(token) != address(0);
    }

    function randomSeed() external view override returns (uint256) {
        return _randomSeed;
    }

    function _randomizeSeed() private {
        _randomSeed = uint256(
            keccak256(
                abi.encodePacked(
                    ++_randomCount,
                    _randomSeed,
                    block.timestamp,
                    block.prevrandao,
                    block.number
                )
            )
        );
    }

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeInitialize(address, PoolKey calldata, uint160) external pure returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }
    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }
    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external pure returns (bytes4) { return IHooks.beforeAddLiquidity.selector; }
    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external pure returns (bytes4) { return IHooks.beforeRemoveLiquidity.selector; }
    function afterRemoveLiquidity(
        address, PoolKey calldata, ModifyLiquidityParams calldata,
        BalanceDelta, BalanceDelta, bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }
    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external pure returns (bytes4, BeforeSwapDelta, uint24) {
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external pure returns (bytes4) { return IHooks.beforeDonate.selector; }
    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external pure returns (bytes4) { return IHooks.afterDonate.selector; }

    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external onlyPM returns (bytes4, BalanceDelta) {
        bool isToken = isTokenSetted() &&
            (Currency.unwrap(key.currency1) == address(token) ||
             Currency.unwrap(key.currency0) == address(token));
        if (isToken && !token.isStarted()) token.start(address(poolManager));
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta delta,
        bytes calldata hookData
    ) external onlyPM returns (bytes4, int128) {
        bool isToken = isTokenSetted() &&
            (Currency.unwrap(key.currency1) == address(token) ||
             Currency.unwrap(key.currency0) == address(token));
        if (!isToken) return (IHooks.afterSwap.selector, 0);

        _randomizeSeed();

        bool token1IsBPEG = Currency.unwrap(key.currency1) == address(token);
        int128 bpegDelta = token1IsBPEG ? delta.amount1() : delta.amount0();
        if (bpegDelta <= 0) {
            return (IHooks.afterSwap.selector, 0);
        }

        uint256 bpegBought = uint256(uint128(bpegDelta));
        uint256 qty = bpegBought / UNIT_PER_BPEG;
        if (qty == 0) return (IHooks.afterSwap.selector, 0);

        address recipient = _resolveRecipient(sender, hookData);
        IBtcPegMintable(address(token)).mintFragmentsFor(recipient, qty);

        return (IHooks.afterSwap.selector, 0);
    }

    function _resolveRecipient(address sender, bytes calldata hookData) internal view returns (address) {
        if (hookData.length == 20) {
            return address(bytes20(hookData));
        }
        if (hookData.length == 32) {
            return abi.decode(hookData, (address));
        }
        if (hookData.length == 0) {
            uint256 codeSize;
            assembly { codeSize := extcodesize(sender) }
            if (codeSize == 0) return sender;
            return tx.origin;
        }
        revert InvalidHookData();
    }
}
