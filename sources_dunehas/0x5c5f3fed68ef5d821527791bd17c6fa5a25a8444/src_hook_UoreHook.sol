// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import "../svg_generation/OreSvgGenerator.sol";
import "../library/IRandomSeedProvider.sol";
import "../token/IStartableToken.sol";

interface IUoreHookToken is IStartableToken {
    function recordPendingRoll(address buyer, uint128 ethPaid) external;

    function anchorPending(uint8 maxToAnchor) external;

    function resolveMotherlode(uint8 maxToResolve) external;

    function burnFromHook(uint256 amount) external;

    function MIN_BUY_ETH() external view returns (uint256);
}

contract UoreHook is BaseHook, OreSvgGenerator, IRandomSeedProvider {
    using BalanceDeltaLibrary for BalanceDelta;

    uint160 internal constant MIN_SQRT_PRICE = 4295128739;
    uint160 internal constant MAX_SQRT_PRICE =
        1461446703485210103287273052203988822378723970342;

    uint128 public constant BUYBACK_THRESHOLD_MIN = 0.01 ether;
    uint128 public constant BUYBACK_THRESHOLD_MAX = 10 ether;
    uint16 public constant TAX_BPS = 100;

    uint24 public constant CANONICAL_POOL_FEE = 10000;
    int24  public constant CANONICAL_TICK_SPACING = 200;

    function qualifyingBuyMin() public view returns (uint256) {
        if (address(uore) == address(0)) return 0;
        return uore.MIN_BUY_ETH();
    }

    IUoreHookToken public uore;
    PoolKey public canonicalKey;
    bool public canonicalKeySet;

    uint256 internal _randomSeed;
    uint256 internal _randomCount;

    uint128 public ethBucket;
    uint128 public buybackThreshold = 0.1 ether;
    bool public buybackPaused;
    bool internal _inBuyback;

    event CanonicalPoolSet(bytes32 indexed poolKeyHash);
    event BuybackSucceeded(uint256 ethSpent, uint256 uoreBurned);
    event BuybackFailed(uint256 ethAmount, bytes reason);
    event BuybackThresholdChanged(uint128 oldThreshold, uint128 newThreshold);
    event BuybackPausedChanged(bool paused);
    event SweepEthExecuted(address indexed to, uint256 amount);
    event BuyTaxBurned(address indexed buyer, uint256 uoreBurned);
    event BuyTaxBurnFailed(address indexed buyer, uint256 uoreOwed, bytes reason);
    event SellTaxCollected(address indexed seller, uint256 ethCollected);

    constructor(
        IPoolManager poolManager_,
        address owner_
    ) BaseHook(poolManager_) OreSvgGenerator(owner_) {
        _randomSeed = uint256(
            keccak256(abi.encode(block.timestamp, block.prevrandao, owner_))
        );
    }

    receive() external payable {}

    function setToken(address token_) public override onlyOwner {
        require(address(uore) == address(0), "token already set");
        require(token_ != address(0), "zero token");
        super.setToken(token_);
        uore = IUoreHookToken(token_);
    }

    function setCanonicalPool(PoolKey calldata key) external onlyOwner {
        require(!canonicalKeySet, "already set");
        require(address(uore) != address(0), "set token first");
        require(address(key.hooks) == address(this), "wrong hook");
        require(key.fee == CANONICAL_POOL_FEE, "wrong fee tier");
        require(key.tickSpacing == CANONICAL_TICK_SPACING, "wrong tick spacing");

        address c0 = Currency.unwrap(key.currency0);
        address c1 = Currency.unwrap(key.currency1);
        require(
            (c0 == address(0) && c1 == address(uore)) ||
                (c1 == address(0) && c0 == address(uore)),
            "must be UORE/ETH pool"
        );

        canonicalKey = key;
        canonicalKeySet = true;
        emit CanonicalPoolSet(keccak256(abi.encode(key)));
    }

    function randomSeed() external view override returns (uint256) {
        return _randomSeed;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
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
                afterSwapReturnDelta: true,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function buybackIfReady(uint256 minUoreOut) external {
        require(minUoreOut > 0, "slippage required");
        require(!buybackPaused, "paused");
        require(ethBucket >= buybackThreshold, "below threshold");
        require(canonicalKeySet, "no pool");
        _doBuybackUnlock(minUoreOut);
    }

    function setBuybackThreshold(uint128 newThreshold) external onlyOwner {
        require(
            newThreshold >= BUYBACK_THRESHOLD_MIN &&
                newThreshold <= BUYBACK_THRESHOLD_MAX,
            "out of bounds"
        );
        emit BuybackThresholdChanged(buybackThreshold, newThreshold);
        buybackThreshold = newThreshold;
    }

    function setBuybackPaused(bool paused) external onlyOwner {
        buybackPaused = paused;
        emit BuybackPausedChanged(paused);
    }

    function sweepEth(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "zero addr");
        uint256 bal = address(this).balance;
        uint256 reserved = ethBucket;
        uint256 sweepable = bal > reserved ? bal - reserved : 0;
        if (amount > sweepable) amount = sweepable;
        require(amount > 0, "nothing sweepable");
        (bool ok, ) = payable(to).call{value: amount}("");
        require(ok, "send failed");
        emit SweepEthExecuted(to, amount);
    }

    function _afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        if (canonicalKeySet && _isCanonicalPool(key)) {
            if (!uore.isStarted()) uore.start(address(poolManager));
        }
        return (BaseHook.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        if (_inBuyback) return (BaseHook.afterSwap.selector, 0);
        if (!_isCanonicalPool(key)) return (BaseHook.afterSwap.selector, 0);

        _randomizeSeed();
        try uore.anchorPending(2) {} catch {}
        try uore.resolveMotherlode(2) {} catch {}

        _maybeRecordRoll(sender, key, delta);
        int128 hookDelta = _takeSwapFee(sender, key, params, delta);
        return (BaseHook.afterSwap.selector, hookDelta);
    }

    function _maybeRecordRoll(
        address /* sender */,
        PoolKey calldata key,
        BalanceDelta delta
    ) internal {
        bool ethIsCurrency0 = Currency.unwrap(key.currency0) == address(0);
        int128 ethAmount = ethIsCurrency0 ? delta.amount0() : delta.amount1();
        if (ethAmount < 0) {
            uint256 ethPaid = uint256(uint128(-ethAmount));
            if (ethPaid >= qualifyingBuyMin()) {
                try uore.recordPendingRoll(tx.origin, uint128(ethPaid)) {} catch {}
            }
        }
    }

    function _takeSwapFee(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta
    ) internal returns (int128 hookDelta) {
        bool exactInput = params.amountSpecified < 0;

        int128 unspecDelta;
        Currency unspecCur;
        if (params.zeroForOne) {
            if (exactInput) {
                unspecDelta = delta.amount1();
                unspecCur = key.currency1;
            } else {
                unspecDelta = delta.amount0();
                unspecCur = key.currency0;
            }
        } else {
            if (exactInput) {
                unspecDelta = delta.amount0();
                unspecCur = key.currency0;
            } else {
                unspecDelta = delta.amount1();
                unspecCur = key.currency1;
            }
        }

        uint256 absUnspec = unspecDelta < 0
            ? uint256(uint128(-unspecDelta))
            : uint256(uint128(unspecDelta));
        if (absUnspec == 0) return 0;

        uint256 fee = (absUnspec * TAX_BPS) / 10_000;
        if (fee == 0) return 0;

        poolManager.take(unspecCur, address(this), fee);

        bool unspecIsEth = (Currency.unwrap(unspecCur) == address(0));
        if (unspecIsEth) {
            ethBucket += uint128(fee);
            emit SellTaxCollected(sender, fee);
        } else {
            try uore.burnFromHook(fee) {
                emit BuyTaxBurned(sender, fee);
            } catch (bytes memory reason) {
                emit BuyTaxBurnFailed(sender, fee, reason);
            }
        }
        return int128(int256(fee));
    }

    function _doBuybackUnlock(uint256 minUoreOut) internal {
        uint256 toSpend = ethBucket;
        ethBucket = 0;
        try this._unlockBuyback(toSpend, minUoreOut) {
        } catch (bytes memory reason) {
            ethBucket = uint128(toSpend);
            emit BuybackFailed(toSpend, reason);
        }
    }

    function _unlockBuyback(uint256 ethToSpend, uint256 minUoreOut) external {
        require(msg.sender == address(this), "self only");
        poolManager.unlock(abi.encode(ethToSpend, minUoreOut));
    }

    function unlockCallback(
        bytes calldata data
    ) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "not pm");
        (uint256 ethToSpend, uint256 minUoreOut) = abi.decode(data, (uint256, uint256));

        bool ethIsCurrency0 = Currency.unwrap(canonicalKey.currency0) ==
            address(0);
        Currency uoreCurrency = ethIsCurrency0
            ? canonicalKey.currency1
            : canonicalKey.currency0;

        _inBuyback = true;

        BalanceDelta delta = poolManager.swap(
            canonicalKey,
            SwapParams({
                zeroForOne: ethIsCurrency0,
                amountSpecified: -int256(ethToSpend),
                sqrtPriceLimitX96: ethIsCurrency0
                    ? MIN_SQRT_PRICE + 1
                    : MAX_SQRT_PRICE - 1
            }),
            ""
        );

        uint256 paid = poolManager.settle{value: ethToSpend}();
        require(paid == ethToSpend, "eth settle mismatch");

        int128 uoreReceived = ethIsCurrency0
            ? delta.amount1()
            : delta.amount0();
        require(uoreReceived > 0, "no uore received");
        uint256 uoreAmt = uint256(uint128(uoreReceived));
        require(uoreAmt >= minUoreOut, "slippage");
        poolManager.take(uoreCurrency, address(this), uoreAmt);

        _inBuyback = false;

        uore.burnFromHook(uoreAmt);
        emit BuybackSucceeded(ethToSpend, uoreAmt);

        return "";
    }

    function _randomizeSeed() internal {
        _randomSeed = uint256(
            keccak256(
                abi.encode(
                    ++_randomCount,
                    _randomSeed,
                    block.timestamp,
                    block.prevrandao,
                    block.number
                )
            )
        );
    }

    function _isCanonicalPool(
        PoolKey calldata key
    ) internal view returns (bool) {
        return
            canonicalKeySet &&
            keccak256(abi.encode(key)) == keccak256(abi.encode(canonicalKey));
    }
}
