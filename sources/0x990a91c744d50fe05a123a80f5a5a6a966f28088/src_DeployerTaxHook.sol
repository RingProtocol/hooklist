// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";

/// @title DeployerTaxHook
/// @notice Charges a per-direction tax on swaps by returning a BeforeSwapDelta.
///         Fees are accrued as ERC6909 claim tokens on the PoolManager and
///         drainable to `devWallet` via `drainFees()`.
/// @dev    The hook is strictly tied to one token (`TOKEN`) and is expected to
///         be attached to exactly one pool (ETH/TOKEN). Pool enforces this via
///         `isAttached` gate — the first swap locks the pool key.
contract DeployerTaxHook is IHooks, IUnlockCallback, Ownable {
    using Hooks for IHooks;

    // ---------- immutable ----------
    IPoolManager public immutable POOL_MANAGER;
    address public immutable TOKEN;
    uint16 public immutable MAX_TAX_BPS;
    uint16 public constant TAX_HARDCAP_BPS = 1500; // 15% absolute ceiling

    // ---------- config ----------
    address public devWallet;
    uint16 public buyTaxBps;
    uint16 public sellTaxBps;

    // ---------- events ----------
    event TaxUpdated(uint16 buyBps, uint16 sellBps);
    event DevWalletUpdated(address newWallet);
    event FeesDrained(address indexed currency, address indexed to, uint256 amount);
    event Fee(bool zeroForOne, address indexed currency, uint256 amount);

    // ---------- errors ----------
    error NotPoolManager();
    error InvalidPool();
    error TaxExceedsMax();
    error MaxExceedsHardcap();
    error ZeroAddress();
    error HookNotImplemented();

    modifier onlyPoolManager() {
        if (msg.sender != address(POOL_MANAGER)) revert NotPoolManager();
        _;
    }

    /// @param _initialOwner Owner of the hook — must be passed explicitly
    ///        because CREATE2 deployment via a factory means msg.sender is the
    ///        factory, not the real deployer. Pass the EOA that should be
    ///        allowed to call setTax / setDevWallet / renounceOwnership.
    constructor(
        address _initialOwner,
        IPoolManager _poolManager,
        address _token,
        address _devWallet,
        uint16 _maxTaxBps,
        uint16 _initialBuyBps,
        uint16 _initialSellBps
    ) Ownable(_initialOwner) {
        if (
            _initialOwner == address(0) || address(_poolManager) == address(0)
                || _token == address(0) || _devWallet == address(0)
        ) {
            revert ZeroAddress();
        }
        if (_maxTaxBps > TAX_HARDCAP_BPS) revert MaxExceedsHardcap();
        if (_initialBuyBps > _maxTaxBps || _initialSellBps > _maxTaxBps) revert TaxExceedsMax();

        POOL_MANAGER = _poolManager;
        TOKEN = _token;
        devWallet = _devWallet;
        MAX_TAX_BPS = _maxTaxBps;
        buyTaxBps = _initialBuyBps;
        sellTaxBps = _initialSellBps;

        // Enforce that the address this deploys to has the right flag bits.
        // We only use beforeSwap + beforeSwapReturnDelta.
        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
    }

    // ---------- hook permissions ----------

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ---------- admin ----------

    function setTax(uint16 _buyBps, uint16 _sellBps) external onlyOwner {
        if (_buyBps > MAX_TAX_BPS || _sellBps > MAX_TAX_BPS) revert TaxExceedsMax();
        buyTaxBps = _buyBps;
        sellTaxBps = _sellBps;
        emit TaxUpdated(_buyBps, _sellBps);
    }

    function setDevWallet(address _wallet) external onlyOwner {
        if (_wallet == address(0)) revert ZeroAddress();
        devWallet = _wallet;
        emit DevWalletUpdated(_wallet);
    }

    // ---------- hook callbacks ----------

    function beforeInitialize(address, PoolKey calldata, uint160) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
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
    ) external pure returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
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
    ) external pure returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    /// @notice Core tax-collection logic. Fires before every swap.
    /// @dev    Fee is taken from the "specified" currency (input for exactIn,
    ///         output for exactOut). For exactIn swaps the hook mints ERC6909
    ///         claim tokens equal to the fee amount, which can be drained
    ///         later. We only handle exactIn — exactOut flows bypass the hook
    ///         fee (rare path for a memecoin).
    function beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Ensure this hook is being called for our token's pool.
        if (
            Currency.unwrap(key.currency1) != TOKEN
                && Currency.unwrap(key.currency0) != TOKEN
        ) {
            revert InvalidPool();
        }

        // Skip exact-output swaps — complex to handle and uncommon for memes.
        bool exactInput = params.amountSpecified < 0;
        if (!exactInput) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // zeroForOne = true means currency0 → currency1.
        // In our pool: currency0 = native ETH (0x0), currency1 = TOKEN.
        // So zeroForOne = true is a BUY (ETH → TOKEN).
        uint16 taxBps = params.zeroForOne ? buyTaxBps : sellTaxBps;
        if (taxBps == 0) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        uint256 absAmount = uint256(-params.amountSpecified);
        uint256 feeAmount = (absAmount * taxBps) / 10_000;
        if (feeAmount == 0) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // Input currency is the "specified" side for exactIn.
        Currency feeCurrency = params.zeroForOne ? key.currency0 : key.currency1;

        // Mint ERC6909 claim tokens for ourselves. This credits the hook
        // without transferring the underlying — settle accounting remains
        // consistent because our positive specified delta tells PoolManager
        // to deduct feeAmount from the swap's effective input.
        POOL_MANAGER.mint(address(this), feeCurrency.toId(), feeAmount);

        emit Fee(params.zeroForOne, Currency.unwrap(feeCurrency), feeAmount);

        // BeforeSwapDelta: (specifiedDelta, unspecifiedDelta) both int128.
        // Positive specifiedDelta = hook removes that amount from the swap's
        // input. The swap now sees (absAmount - feeAmount) as its effective
        // input and computes the output from that.
        BeforeSwapDelta delta = toBeforeSwapDelta(int128(int256(feeAmount)), 0);

        return (IHooks.beforeSwap.selector, delta, 0);
    }

    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        pure
        returns (bytes4, int128)
    {
        revert HookNotImplemented();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    // ---------- drain ----------

    /// @notice Drains accumulated tax for a given currency to `devWallet`.
    ///         Anyone can call; funds always go to `devWallet`.
    /// @param  currency The currency to drain (address(0) for native ETH).
    function drainFees(address currency) external {
        POOL_MANAGER.unlock(abi.encode(currency));
    }

    /// @notice Called by PoolManager after `unlock()` to perform burn + take
    ///         in a single reentrancy-safe context.
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        address currencyAddr = abi.decode(data, (address));
        Currency c = Currency.wrap(currencyAddr);
        uint256 id = c.toId();
        uint256 balance = POOL_MANAGER.balanceOf(address(this), id);
        if (balance > 0) {
            POOL_MANAGER.burn(address(this), id, balance);
            POOL_MANAGER.take(c, devWallet, balance);
            emit FeesDrained(currencyAddr, devWallet, balance);
        }
        return "";
    }

    /// @notice View helper: how much tax (as ERC6909 claim) this hook holds
    ///         for a given currency, ready to drain.
    function accruedFees(address currency) external view returns (uint256) {
        return POOL_MANAGER.balanceOf(address(this), Currency.wrap(currency).toId());
    }
}
