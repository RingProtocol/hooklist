// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Wei — project website: https://0xwei.com

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";

import {WeiToken} from "./WeiToken.sol";
import {WeiCurve} from "./lib/WeiCurve.sol";

contract WeiHook is IHooks {
    // ---- locked parameters -------------------------------------------------

    /// @notice Asymptotic supply cap of the curve (1B WEI).
    uint256 public constant K_SUPPLY = 1_000_000_000e18;

    /// @notice Curve elasticity / EIP-1559 base-fee target (155.9 ETH).
    uint256 public constant T_TARGET = 155_900_000_000_000_000_000;

    /// @notice Per-buy ETH cap inside the entropy window (first 100 blocks).
    uint256 public constant MAX_BUY_BOOTSTRAP = 1 ether;

    /// @notice Per-buy ETH cap after the entropy window.
    uint256 public constant MAX_BUY_STEADY = 5 ether;

    /// @notice Cooldown between a wallet's last buy and its first sell (1 block).
    uint256 public constant COOLDOWN_BLOCKS = 1;

    /// @notice Pool fee in V4 hundredths-of-bips. Zero — no LP fee at the V4 level
    ///         because the pool has no liquidity providers; the wei-side fee
    ///         routed to the black hole is the only fee.
    uint24 public constant POOL_FEE = 0;

    /// @notice Number of blocks during which buys receive an entropy multiplier.
    uint256 public constant ENTROPY_BLOCKS = 100;

    /// @notice Numerator of the self-deprecation threshold (99/100 of K_SUPPLY).
    uint256 public constant EXHAUSTION_THRESHOLD_NUMERATOR = 99;
    uint256 public constant EXHAUSTION_THRESHOLD_DENOMINATOR = 100;

    /// @notice Black-hole sink for protocol-fee WEI and redeemed WEI. Standard
    ///         Etherscan-recognised burn address; tokens sent here are inert —
    ///         no key controls them, no contract logic moves them out.
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;

    /// @notice Protocol fee rate: 1559 / 1_000_000 = 0.1559% (echoes EIP-1559).
    uint256 internal constant FEE_NUMERATOR = 1559;
    uint256 internal constant FEE_DENOMINATOR = 1_000_000;

    // ---- immutables --------------------------------------------------------

    IPoolManager public immutable POOL_MANAGER;
    WeiToken public immutable WEI_TOKEN;
    Currency public immutable ETH_CURRENCY;
    Currency public immutable WEI_CURRENCY;
    uint256 public immutable GENESIS_BLOCK;
    bytes32 public immutable GENESIS_HASH;

    // ---- storage -----------------------------------------------------------

    /// @notice The manifesto, eight 32-byte words. Set in constructor; never modified.
    bytes32[8] private _GENESIS_MESSAGE;

    /// @notice Cumulative ETH that has flowed into the curve (buys add, sells subtract).
    ///         Equals address(this).balance under the no-ETH-fee design.
    uint256 public ethCum;

    /// @notice Fair-curve circulating supply: tokens that map onto `ethCum` via the forward curve.
    ///         Differs from `circulatingSupply()` (= totalSupply − blackHole balance) because of
    ///         (a) buy-side fee minted to the black hole, (b) sell-side fee transferred to the
    ///         black hole, and (c) entropy multipliers. The sell-side redemption portion is
    ///         permanently destroyed via `WeiToken.burn`, so it leaves no trace in either term.
    uint256 public totalMintedFair;

    /// @notice Whether the curve has irreversibly entered self-deprecation. After this, no buys.
    bool public selfDeprecated;

    /// @notice Whether the pool has been initialized.
    bool public poolInitialized;

    /// @notice The block of each address's last buy, indexed by hookData-supplied swapper.
    mapping(address account => uint256 blockNumber) public lastBuyBlock;

    // ---- errors ------------------------------------------------------------

    error NotPoolManager();
    error InvalidPool();
    error LiquidityAdditionsForbidden();
    error BuyTooLarge();
    error CooldownActive();
    error SelfDeprecatedNoBuys();
    error ExactOutputUnsupported();
    error MissingSwapperInHookData();
    error InsufficientEthReserves();

    // ---- constructor -------------------------------------------------------

    /// @param poolManager The Uniswap V4 PoolManager.
    /// @param weiToken    The Wei ERC-20 (this hook will be set as its sole minter).
    /// @param manifesto   The 8x32-byte manifesto string, padded with trailing zeros.
    constructor(IPoolManager poolManager, WeiToken weiToken, bytes32[8] memory manifesto) {
        POOL_MANAGER = poolManager;
        WEI_TOKEN = weiToken;
        ETH_CURRENCY = Currency.wrap(address(0));
        WEI_CURRENCY = Currency.wrap(address(weiToken));
        GENESIS_BLOCK = block.number;
        GENESIS_HASH = block.number == 0 ? bytes32(0) : blockhash(block.number - 1);
        for (uint256 i = 0; i < 8; ++i) {
            _GENESIS_MESSAGE[i] = manifesto[i];
        }
        Hooks.validateHookPermissions(this, getHookPermissions());
    }

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
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

    function philosophy() external view returns (string memory) {
        bytes memory raw = new bytes(256);
        for (uint256 i = 0; i < 8; ++i) {
            bytes32 word = _GENESIS_MESSAGE[i];
            for (uint256 j = 0; j < 32; ++j) {
                raw[i * 32 + j] = word[j];
            }
        }
        uint256 len = 256;
        while (len > 0 && raw[len - 1] == 0x00) {
            unchecked { --len; }
        }
        bytes memory trimmed = new bytes(len);
        for (uint256 k = 0; k < len; ++k) {
            trimmed[k] = raw[k];
        }
        return string(trimmed);
    }

    function maxBuyWei() public view returns (uint256) {
        return block.number <= GENESIS_BLOCK + ENTROPY_BLOCKS ? MAX_BUY_BOOTSTRAP : MAX_BUY_STEADY;
    }

    function curveReserveEth() external view returns (uint256) {
        return address(this).balance;
    }

    function circulatingSupply() public view returns (uint256) {
        return WEI_TOKEN.totalSupply() - WEI_TOKEN.balanceOf(BLACK_HOLE);
    }

    // ---- modifiers ---------------------------------------------------------

    modifier onlyPoolManager() {
        if (msg.sender != address(POOL_MANAGER)) revert NotPoolManager();
        _;
    }

    // ---- v4 hook entrypoints ----------------------------------------------

    function beforeInitialize(address, PoolKey calldata key, uint160) external onlyPoolManager returns (bytes4) {
        if (Currency.unwrap(key.currency0) != address(0)) revert InvalidPool();
        if (Currency.unwrap(key.currency1) != address(WEI_TOKEN)) revert InvalidPool();
        if (key.fee != POOL_FEE) revert InvalidPool();
        if (address(key.hooks) != address(this)) revert InvalidPool();
        poolInitialized = true;
        return IHooks.beforeInitialize.selector;
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4)
    {
        revert LiquidityAdditionsForbidden();
    }

    function beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        onlyPoolManager
        returns (bytes4 selector, BeforeSwapDelta delta, uint24 lpFeeOverride)
    {
        if (params.amountSpecified >= 0) revert ExactOutputUnsupported();
        if (Currency.unwrap(key.currency0) != address(0) || Currency.unwrap(key.currency1) != address(WEI_TOKEN)) {
            revert InvalidPool();
        }
        if (hookData.length < 32) revert MissingSwapperInHookData();
        address swapper = abi.decode(hookData, (address));

        if (params.zeroForOne) {
            return _executeBuy(uint256(-params.amountSpecified), swapper);
        } else {
            return _executeSell(uint256(-params.amountSpecified), swapper);
        }
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }
    function afterAddLiquidity(
        address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }
    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external pure returns (bytes4)
    {
        return IHooks.beforeRemoveLiquidity.selector;
    }
    function afterRemoveLiquidity(
        address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }
    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        external pure returns (bytes4, int128)
    {
        return (IHooks.afterSwap.selector, int128(0));
    }
    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external pure returns (bytes4)
    {
        return IHooks.beforeDonate.selector;
    }
    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external pure returns (bytes4)
    {
        return IHooks.afterDonate.selector;
    }

    function _executeBuy(uint256 ethIn, address swapper)
        internal
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (selfDeprecated) revert SelfDeprecatedNoBuys();
        if (ethIn > maxBuyWei()) revert BuyTooLarge();

        uint256 fairWei = WeiCurve.mintFor(ethCum, ethIn);
        uint256 feeWei  = (fairWei * FEE_NUMERATOR) / FEE_DENOMINATOR;
        uint256 payWei  = _applyEntropy(fairWei - feeWei, swapper, ethIn);

        ethCum += ethIn;
        totalMintedFair += fairWei;
        lastBuyBlock[swapper] = block.number;
        if (
            totalMintedFair * EXHAUSTION_THRESHOLD_DENOMINATOR
                >= K_SUPPLY * EXHAUSTION_THRESHOLD_NUMERATOR
        ) {
            selfDeprecated = true;
        }

        POOL_MANAGER.sync(WEI_CURRENCY);
        WEI_TOKEN.mint(address(POOL_MANAGER), payWei);
        if (feeWei > 0) WEI_TOKEN.mint(BLACK_HOLE, feeWei);
        POOL_MANAGER.settle();
        POOL_MANAGER.take(ETH_CURRENCY, address(this), ethIn);

        BeforeSwapDelta delta = toBeforeSwapDelta(int128(int256(ethIn)), -int128(int256(payWei)));
        return (IHooks.beforeSwap.selector, delta, 0);
    }

    function _executeSell(uint256 weiIn, address swapper)
        internal
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Same-block cooldown vs this seller's last buy.
        uint256 lastBlock = lastBuyBlock[swapper];
        if (lastBlock != 0 && (block.number - lastBlock) < COOLDOWN_BLOCKS) revert CooldownActive();

        uint256 feeWei = (weiIn * FEE_NUMERATOR) / FEE_DENOMINATOR;
        uint256 effectiveWei = weiIn - feeWei;

        uint256 actualSupply = WEI_TOKEN.totalSupply() - WEI_TOKEN.balanceOf(BLACK_HOLE);
        uint256 fairIn = (effectiveWei * totalMintedFair) / actualSupply;
        if (fairIn > totalMintedFair) fairIn = totalMintedFair;
 
        uint256 ethRaw = fairIn == 0 ? 0 : WeiCurve.burnFor(totalMintedFair, fairIn);

        if (address(this).balance < ethRaw) revert InsufficientEthReserves();

        // Effects first (CEI): retract curve state before any external call.
        if (ethRaw <= ethCum) {
            ethCum -= ethRaw;
        } else {
            ethCum = 0;
        }
        totalMintedFair -= fairIn;

        if (feeWei > 0) POOL_MANAGER.take(WEI_CURRENCY, BLACK_HOLE, feeWei);
        if (effectiveWei > 0) {
            POOL_MANAGER.take(WEI_CURRENCY, address(this), effectiveWei);
            WEI_TOKEN.burn(effectiveWei);
        }
        POOL_MANAGER.settle{value: ethRaw}();

        BeforeSwapDelta delta = toBeforeSwapDelta(int128(int256(weiIn)), -int128(int256(ethRaw)));
        return (IHooks.beforeSwap.selector, delta, 0);
    }

    function _applyEntropy(uint256 fairAmount, address swapper, uint256 ethIn) internal view returns (uint256) {
        if (block.number >= GENESIS_BLOCK + ENTROPY_BLOCKS) return fairAmount;
        bytes32 h = keccak256(abi.encodePacked(blockhash(block.number - 1), swapper, ethIn));
        uint256 mul = 9000 + (uint256(h) % 2001); // 9000..11000, in 1e-4 units
        return (fairAmount * mul) / 10000;
    }

    receive() external payable {}
}
