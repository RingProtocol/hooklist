// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";

interface IUnicoreRewardSink {
    function depositRewards() external payable;
}

/// @title UnicoreHook
/// @notice Uniswap v4 hook that takes a flat 3% native-ETH tax on every swap and pushes the
///         tax into the UnicoreToken's reward distributor. No volatility tracking, no team
///         split. The hook accumulates tax (ERC-6909 claims for buy-side input tax, physical
///         ETH for sell-side output tax) and any keeper or user can call `normalize()` to
///         convert claims to ETH and push everything to the token in one shot.
contract UnicoreHook is IHooks, IUnlockCallback {
    using CurrencyLibrary for Currency;

    uint24 public constant TAX_BIPS = 300;
    uint24 public constant BIPS_DENOMINATOR = 10_000;

    IPoolManager public immutable poolManager;
    IUnicoreRewardSink public immutable token;

    address public owner;
    address public pendingOwner;

    /// @notice Rolling per-swap entropy. Every swap stamps this hook with a fresh value
    ///         derived from the previous entropy plus block randomness and the swap's own
    ///         parameters, so two swaps in the same block produce different seeds.
    bytes32 public swapEntropy;

    event OwnerTransferProposed(address indexed currentOwner, address indexed pendingOwner);
    event OwnerTransferred(address indexed oldOwner, address indexed newOwner);
    event RewardsPushedToToken(uint256 amount);
    event SwapEntropyAdvanced(bytes32 newEntropy);

    error Unauthorized();
    error InvalidOwner();
    error HookNotImplemented();
    error ExactOutputUnsupported();
    error PartialFillUnsupported();
    error AmountTooLarge();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert Unauthorized();
        _;
    }

    constructor(IPoolManager poolManager_, IUnicoreRewardSink token_, address owner_) {
        poolManager = poolManager_;
        token = token_;
        owner = owner_;
        emit OwnerTransferred(address(0), owner_);
    }

    // --------------------------------------------------------------- ownership

    function transferOwner(address newOwner) external onlyOwner {
        pendingOwner = newOwner;
        emit OwnerTransferProposed(owner, newOwner);
    }

    function acceptOwner() external {
        if (msg.sender != pendingOwner) revert Unauthorized();
        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnerTransferred(oldOwner, msg.sender);
    }

    function currentTaxBips() external pure returns (uint24) {
        return TAX_BIPS;
    }

    // ------------------------------------------------------------------ hooks

    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Advance the per-swap entropy. This is what makes randomly-rolled rarities a function
        // of market activity (Unipeg-style): two swaps in the same block produce different seeds.
        bytes32 newEntropy = keccak256(
            abi.encode(swapEntropy, block.prevrandao, block.number, block.timestamp, sender, key, params, hookData)
        );
        swapEntropy = newEntropy;
        emit SwapEntropyAdvanced(newEntropy);

        (BeforeSwapDelta delta, int128 tax) = _beforeSwapTaxDelta(key, params);
        if (tax != 0) {
            poolManager.mint(address(this), CurrencyLibrary.ADDRESS_ZERO.toId(), SafeCast.toUint128(tax));
        }
        return (IHooks.beforeSwap.selector, delta, 0);
    }

    /// @notice Returns a fresh seed for a new mint by mixing the rolling swapEntropy with
    ///         caller-supplied context (typically the buyer's address + slot index). Pure view —
    ///         the entropy itself only advances inside beforeSwap.
    function randomSeed(bytes32 context) external view returns (bytes32) {
        return keccak256(abi.encode(swapEntropy, context));
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        _validateNoPartialSpecifiedFill(key, params, delta);
        int128 tax = _afterSwapTaxDelta(key, params, delta);
        if (tax != 0) {
            poolManager.take(CurrencyLibrary.ADDRESS_ZERO, address(this), SafeCast.toUint128(tax));
        }
        return (IHooks.afterSwap.selector, tax);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    // -------------------------------------------------------- tax computation

    function quoteBeforeSwapTax(PoolKey calldata key, SwapParams calldata params)
        external
        view
        returns (BeforeSwapDelta)
    {
        (BeforeSwapDelta delta,) = _beforeSwapTaxDelta(key, params);
        return delta;
    }

    function quoteAfterSwapTax(PoolKey calldata key, SwapParams calldata params, BalanceDelta delta)
        external
        view
        returns (int128)
    {
        return _afterSwapTaxDelta(key, params, delta);
    }

    function _beforeSwapTaxDelta(PoolKey calldata key, SwapParams calldata params)
        internal
        pure
        returns (BeforeSwapDelta delta, int128 tax)
    {
        if (params.amountSpecified > 0) revert ExactOutputUnsupported();

        Currency specifiedCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        if (!specifiedCurrency.isAddressZero()) {
            return (BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        uint256 amountIn = uint256(-params.amountSpecified);
        tax = _taxAmount(amountIn);
        if (tax == 0) return (BeforeSwapDeltaLibrary.ZERO_DELTA, 0);

        delta = toBeforeSwapDelta(tax, 0);
    }

    function _afterSwapTaxDelta(PoolKey calldata key, SwapParams calldata params, BalanceDelta delta)
        internal
        pure
        returns (int128)
    {
        if (params.amountSpecified > 0) revert ExactOutputUnsupported();

        Currency unspecifiedCurrency = params.zeroForOne ? key.currency1 : key.currency0;
        if (!unspecifiedCurrency.isAddressZero()) return 0;

        int128 rewardOutput = key.currency0.isAddressZero() ? delta.amount0() : delta.amount1();
        if (rewardOutput <= 0) return 0;

        return _taxAmount(SafeCast.toUint128(rewardOutput));
    }

    function _validateNoPartialSpecifiedFill(PoolKey calldata key, SwapParams calldata params, BalanceDelta delta)
        internal
        pure
    {
        if (params.amountSpecified > 0) return;

        Currency specifiedCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        if (!specifiedCurrency.isAddressZero()) return;

        uint256 amountIn = uint256(-params.amountSpecified);
        int128 tax = _taxAmount(amountIn);
        uint256 expectedSwapInput = amountIn - SafeCast.toUint128(tax);
        int128 actualSpecifiedDelta =
            specifiedCurrency.isAddressZero() && key.currency0.isAddressZero() ? delta.amount0() : delta.amount1();

        if (actualSpecifiedDelta >= 0 || SafeCast.toUint128(-actualSpecifiedDelta) != expectedSwapInput) {
            revert PartialFillUnsupported();
        }
    }

    function _taxAmount(uint256 amount) internal pure returns (int128) {
        uint256 tax = (amount * TAX_BIPS) / BIPS_DENOMINATOR;
        if (tax > uint256(uint128(type(int128).max))) revert AmountTooLarge();
        return SafeCast.toInt128(tax);
    }

    // ----------------------------------------------------------- normalization

    /// @notice Convert any accumulated ERC-6909 native-ETH claims held by this hook into
    ///         physical ETH, then push the entire ETH balance to the token's reward
    ///         distributor. Permissionless on purpose — there is nothing to grief here, the
    ///         caller can only ever speed up reward distribution.
    function normalize() external returns (uint256 amount) {
        uint256 claimAmount =
            poolManager.balanceOf(address(this), CurrencyLibrary.ADDRESS_ZERO.toId());
        if (claimAmount != 0) {
            poolManager.unlock(abi.encode(claimAmount));
        }

        amount = address(this).balance;
        if (amount != 0) {
            token.depositRewards{value: amount}();
            emit RewardsPushedToToken(amount);
        }
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert Unauthorized();
        uint256 amount = abi.decode(data, (uint256));

        poolManager.burn(address(this), CurrencyLibrary.ADDRESS_ZERO.toId(), amount);
        poolManager.take(CurrencyLibrary.ADDRESS_ZERO, address(this), amount);

        return abi.encode(amount);
    }

    receive() external payable {}
}
