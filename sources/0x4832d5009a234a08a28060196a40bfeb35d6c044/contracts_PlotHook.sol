// SPDX-License-Identifier: MIT
//
//    UniLand — random plot lottery powered by a Uniswap V4 hook
//      X       : https://x.com/UniLandHooks
//      Website : https://unilandhooks.fun
//
pragma solidity ^0.8.26;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {IPlotHook} from "./interfaces/IPlotHook.sol";
import {IPlotToken} from "./interfaces/IPlotToken.sol";

/// @title  PlotHook
/// @notice Uniswap V4 hook for UniLand. The pool currency0 is native ETH
///         (`address(0)`); currency1 is the PlotToken.
///
///         - on every swap: bumps a rolling entropy seed
///         - on SELLS (ULand → ETH, exactInput only): takes 3% of output ETH
///           and forwards it to the owner of a randomly drawn plot id, with a
///           fallback to `treasury` if the plot is unowned or the recipient
///           cannot receive ETH (non-payable contract)
///
/// @dev    Permissions: afterSwap + afterSwapReturnDelta = bottom-14 = 0x44.
///         Must be deployed via CREATE2 with mined salt. exactOutput sells skip
///         the fee (rare; aggregator-only edge case).
contract PlotHook is BaseHook, IPlotHook {
    using BalanceDeltaLibrary for BalanceDelta;

    address public override plotToken;
    address public immutable treasury;

    uint16 public constant SELL_TAX_BPS = 300; // 3%
    uint32 public constant TOTAL_PLOTS = 10_000;
    uint16 public constant BPS = 10_000;

    uint256 public override seed;
    uint64 public override swapNonce;
    uint256 private _entropyNonce;

    uint256 public totalTaxCollected;
    uint256 public totalTaxToTreasury;

    event SeedUpdated(uint256 indexed nonce, uint256 newSeed, address sender);
    event PlotTokenSet(address indexed token);
    event TaxRouted(
        bytes32 indexed swapKey,
        uint32  indexed plotId,
        address indexed recipient,
        bool    toTreasury,
        uint256 amount,
        address sender,
        uint256 entropy
    );

    constructor(IPoolManager _poolManager, address _treasury) BaseHook(_poolManager) {
        require(_treasury != address(0), "PlotHook: zero treasury");
        treasury = _treasury;
        seed = uint256(
            keccak256(
                abi.encode(
                    block.timestamp,
                    block.prevrandao,
                    block.number,
                    address(_poolManager)
                )
            )
        );
    }

    /// @notice Receive ETH from PoolManager.take(); we forward to recipient inside the same tx.
    receive() external payable {}

    /// @notice Atomic binding from PlotToken constructor (msg.sender == token).
    function setPlotToken(address _token) external {
        require(plotToken == address(0), "PlotHook: token already set");
        require(_token != address(0), "PlotHook: zero token");
        require(_token == msg.sender, "PlotHook: token must self-register");
        plotToken = _token;
        emit PlotTokenSet(_token);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
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

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        _bumpSeed(sender, params);

        // ETH (address 0) is currency0 in any ETH/X pool because address(0)
        // sorts strictly less than any other address.
        bool ethIsCurrency0 = Currency.unwrap(key.currency0) == address(0);
        bool ethIsOutput = (params.zeroForOne && !ethIsCurrency0) ||
                           (!params.zeroForOne && ethIsCurrency0);

        if (!ethIsOutput) return (IHooks.afterSwap.selector, int128(0));

        // exactInput only: amountSpecified < 0
        if (params.amountSpecified >= 0) return (IHooks.afterSwap.selector, int128(0));

        int128 ethOut = ethIsCurrency0 ? delta.amount0() : delta.amount1();
        if (ethOut <= 0) return (IHooks.afterSwap.selector, int128(0));

        uint256 fee;
        unchecked {
            fee = (uint256(int256(ethOut)) * SELL_TAX_BPS) / BPS;
        }
        if (fee == 0) return (IHooks.afterSwap.selector, int128(0));

        _routeFee(sender, fee);
        return (IHooks.afterSwap.selector, int128(int256(fee)));
    }

    function _routeFee(address sender, uint256 fee) internal {
        (uint32 plotId, address candidate, bool toTreasury_, uint256 entropy_) = _rollPlot();

        // Pull ETH from PoolManager into this hook (atomic balance settlement).
        poolManager.take(Currency.wrap(address(0)), address(this), fee);

        // Forward to candidate via low-level call. Fall back to treasury on
        // failure so a non-payable plot owner can never brick the pool.
        address actualRecipient = candidate;
        bool toTreasuryFinal = toTreasury_;
        (bool ok, ) = candidate.call{value: fee, gas: 30_000}("");
        if (!ok) {
            (ok, ) = treasury.call{value: fee, gas: 30_000}("");
            require(ok, "PlotHook: treasury rejected ETH");
            actualRecipient = treasury;
            toTreasuryFinal = true;
        }

        totalTaxCollected += fee;
        if (toTreasuryFinal) totalTaxToTreasury += fee;

        emit TaxRouted(
            keccak256(abi.encode(sender, swapNonce)),
            plotId,
            actualRecipient,
            toTreasuryFinal,
            fee,
            sender,
            entropy_
        );
    }

    function _bumpSeed(address sender, SwapParams calldata params) internal {
        unchecked {
            uint64 newNonce = swapNonce + 1;
            uint256 newSeed = uint256(
                keccak256(
                    abi.encode(
                        seed,
                        newNonce,
                        sender,
                        params.zeroForOne,
                        params.amountSpecified,
                        block.number,
                        block.prevrandao,
                        blockhash(block.number - 1)
                    )
                )
            );
            seed = newSeed;
            swapNonce = newNonce;
            emit SeedUpdated(newNonce, newSeed, sender);
        }
    }

    function _rollPlot()
        internal
        returns (uint32 plotId, address recipient, bool toTreasury_, uint256 entropy_)
    {
        unchecked { ++_entropyNonce; }
        entropy_ = uint256(
            keccak256(abi.encode(seed, _entropyNonce, block.number, block.prevrandao))
        );
        plotId = uint32((entropy_ % TOTAL_PLOTS) + 1);
        address owner_ = IPlotToken(plotToken).plotOwner(plotId);
        if (owner_ == address(0)) {
            recipient = treasury;
            toTreasury_ = true;
        } else {
            recipient = owner_;
            toTreasury_ = false;
        }
    }
}
