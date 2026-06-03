// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&-MEMS2025-&&&&&&&&&&&&&&&&BOOM&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&                 &&&&&&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&                         &&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&                         &&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&   &&&&&&&&&&&&&&               &&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&  &&&&&&&&&&&&&&&&&&&           &&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&& &&&&&&&&&&&&&&&&&&&           &&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&& &&&&&&&&&&&&&&&&&&           &&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&           &&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&           &&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&           &&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&           &&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&           &&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&           &&&&&&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&           &&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&           &&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&       &&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&       &&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&       &&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&                   &&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&&&&&                   &&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&&&&&    &&&&&&&&&&&&&&&&&&&    &&&&&&&&&&&&&&&&&&&&&&&&&&&&
&&&&1986&&&&&&&&&&&&&#                      &&&&       &&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&#                      &&&&       &&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&&&&#   &&&&&&&&&&&&&&&&&&&    &&&&   &&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&                       &&&&&&&       &&&&&&&&&&&&&&&&&&&&&&&&&
&&&&&&&&&&&&&&&&&&                       &&&&&&&       &&&&&&&&&&&&&&&&&&&&&&&&&

    ╔═══════════════════════════════════════════════════════════════╗
    ║                 MEMESTRATEGY HOOK v1.1                        ║
    ║              Dynamic Fee System (50% → 10-90%)                ║
    ╚═══════════════════════════════════════════════════════════════╝
*/

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @notice Minimal interface for Strategy contract
interface IStrategy {
    function addFeesETH() external payable;
    function tradingEnabled() external view returns (bool);
}

/// @title MemeStrategyHook
/// @notice Uniswap V4 hook that collects dynamic swap fees (Phase 1: 50%, Phase 2: 10-90%)
/// @dev Implements 3-phase system with asymmetric fees and forwards native ETH to strategy
contract MemeStrategyHook is IHooks {
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeCast for int128;
    using Hooks for IHooks;

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                  CONSTANTS                                   */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    IPoolManager public immutable POOL_MANAGER;
    address public STRATEGY;                    // Mutable: can redirect fees to upgraded strategy
    Currency public immutable ETH_CURRENCY;     // Native ETH
    address public TREASURY;                    // Mutable: can update treasury address
    address public OWNER; // Can enable fees (mutable for renounce)

    // Operator Access
    mapping(address => bool) public operators; // Can enable fees and update tiers

    // Fee Exemption (for modules/extensions that burn tokens)
    mapping(address => bool) public feeExempt; // Whitelisted addresses bypass fees

    // Pending Balances (for deferred settlement - best practice for hooks)
    uint256 public pendingStrategy; // Strategy fees awaiting flush
    uint256 public pendingRake;     // Rake fees awaiting flush

    // Fee Constants
    uint128 public BASE_FEE_BIPS = 1000;                // 10% base fee (mutable)
    uint128 public constant PHASE1_FEE_BIPS = 5000;     // 50% Phase 1 flat fee
    uint128 public constant RAKE_BIPS = 2000;           // 20% of total fee to treasury
    uint128 public constant STRATEGY_BIPS = 8000;       // 80% of total fee to strategy
    uint128 public constant TOTAL_BIPS = 10000;
    uint128 public constant BUY_SPIKE_RATIO = 1000;     // Buys pay 10% of spike increase

    // Phase Control
    bool public feesEnabled;        // Phase 0 control
    bool public phase2Activated;    // Phase 2 activation

    // Dynamic Fee System (Phase 2)
    struct FeeSpike {
        uint256 triggerAmount;    // ETH threshold
        uint256 feePercent;       // Fee % in bips
        uint256 decayHours;       // Decay duration
    }

    FeeSpike[10] public feeSpikeTiers;   // 2 ETH to 50 ETH tiers
    uint256 public currentFeeSpike;      // Current spike fee %
    uint256 public feeSpikeTriggerTime;  // When spike started
    uint256 public feeDecayDuration;     // Decay duration in seconds

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                    EVENTS                                    */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    // Access Control Events
    event OperatorAdded(address indexed operator);
    event OperatorRemoved(address indexed operator);
    event OwnershipRenounced(address indexed previousOwner, uint256 timestamp);
    event FeeExemptionSet(address indexed account, bool exempt);
    event StrategyUpdated(address indexed oldStrategy, address indexed newStrategy);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    // Phase Events
    event FeesEnabled(uint256 timestamp);
    event FeesDisabled(uint256 timestamp);
    event FirstSaleExecuted(uint256 saleAmount, uint256 timestamp);
    event Phase2Activated(uint256 timestamp);
    event FeeSpikeTriggered(
        uint256 saleAmount,
        uint256 feePercent,
        uint256 decayHours
    );

    // Fee Events
    event FeeCollected(
        Currency indexed currency,
        uint256 totalFee,
        uint256 strategyAmount,
        uint256 rakeAmount,
        uint256 feeBips
    );
    event FeesFlushedToStrategy(uint256 amount);
    event StrategyFlushFailed(uint256 amount);
    event RakeFlushed(address indexed treasury, uint256 amount);
    event RakeFlushFailed(uint256 amount);

    // Fee Tier Management
    event FeeTierUpdated(
        uint256 indexed index,
        uint256 triggerAmount,
        uint256 feePercent,
        uint256 decayHours
    );
    event AllFeeTiersUpdated();
    event FeeTiersBootstrapped();  // Emitted once in constructor
    event BaseFeeUpdated(uint256 oldBaseFee, uint256 newBaseFee);

    // Emergency Events
    event EmergencyWithdrawETH(address indexed to, uint256 amount);
    event Received(address indexed sender, uint256 amount);

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                    ERRORS                                    */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    error InvalidStrategy();
    error InvalidTreasury();
    error InvalidOwner();
    error InvalidOperator();
    error InvalidAddress();
    error OnlyPoolManager();
    error OnlyStrategy();
    error OnlyOwner();
    error OnlyOwnerOrOperator();
    error FeesAlreadyEnabled();
    error FeesAlreadyDisabled();
    error Phase2AlreadyActive();
    error Phase2NotActive();
    error HookNotImplemented();
    error ExactOutputNotSupported();
    error TradingNotEnabled();

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                 CONSTRUCTOR                                  */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @param _poolManager Uniswap V4 PoolManager
    /// @param _strategy MemeStrategy contract address
    /// @param _treasury Treasury address for 20% rake
    /// @param _owner Owner address (can enable fees)
    constructor(
        IPoolManager _poolManager,
        address _strategy,
        address _treasury,
        address _owner
    ) {
        if (_strategy == address(0)) revert InvalidStrategy();
        if (_treasury == address(0)) revert InvalidTreasury();
        if (_owner == address(0)) revert InvalidOwner();

        POOL_MANAGER = _poolManager;
        STRATEGY = _strategy;
        ETH_CURRENCY = Currency.wrap(address(0));  // Native ETH
        TREASURY = _treasury;
        OWNER = _owner;

        feesEnabled = false;  // Start with fees OFF
        phase2Activated = false;

        // Initialize 10-tier fee spike system
        feeSpikeTiers[0] = FeeSpike({
            triggerAmount: 2 ether,
            feePercent: 1250,
            decayHours: 1
        });
        feeSpikeTiers[1] = FeeSpike({
            triggerAmount: 5 ether,
            feePercent: 1500,
            decayHours: 4
        });
        feeSpikeTiers[2] = FeeSpike({
            triggerAmount: 10 ether,
            feePercent: 2000,
            decayHours: 5
        });
        feeSpikeTiers[3] = FeeSpike({
            triggerAmount: 15 ether,
            feePercent: 2500,
            decayHours: 6
        });
        feeSpikeTiers[4] = FeeSpike({
            triggerAmount: 20 ether,
            feePercent: 4000,
            decayHours: 7
        });
        feeSpikeTiers[5] = FeeSpike({
            triggerAmount: 25 ether,
            feePercent: 5000,
            decayHours: 8
        });
        feeSpikeTiers[6] = FeeSpike({
            triggerAmount: 30 ether,
            feePercent: 6000,
            decayHours: 9
        });
        feeSpikeTiers[7] = FeeSpike({
            triggerAmount: 35 ether,
            feePercent: 7000,
            decayHours: 10
        });
        feeSpikeTiers[8] = FeeSpike({
            triggerAmount: 40 ether,
            feePercent: 8000,
            decayHours: 11
        });
        feeSpikeTiers[9] = FeeSpike({
            triggerAmount: 50 ether,
            feePercent: 9000,
            decayHours: 12
        });

        // Emit bootstrap event for off-chain indexers to cache initial tier configuration
        emit FeeTiersBootstrapped();

        // Validate hook address has correct permissions
        Hooks.validateHookPermissions(
            IHooks(address(this)),
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,                    // ← ENABLED for buy-side fees
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true,         // ← ENABLED for fee collection
                afterSwapReturnDelta: true,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            })
        );
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(POOL_MANAGER)) revert OnlyPoolManager();
        _;
    }

    modifier onlyOwnerOrOperator() {
        if (msg.sender != OWNER && !operators[msg.sender]) revert OnlyOwnerOrOperator();
        _;
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                          OPERATOR MANAGEMENT                                 */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Add operator (can enable fees and update tiers)
    function addOperator(address operator) external {
        if (msg.sender != OWNER) revert OnlyOwner();
        if (operator == address(0)) revert InvalidOperator();
        if (!operators[operator]) {
            operators[operator] = true;
            emit OperatorAdded(operator);
        }
    }

    /// @notice Remove operator
    function removeOperator(address operator) external {
        if (msg.sender != OWNER) revert OnlyOwner();
        if (operators[operator]) {
            operators[operator] = false;
            emit OperatorRemoved(operator);
        }
    }

    /// @notice Renounce ownership (permanently decentralize hook)
    /// @dev IRREVERSIBLE - Sets OWNER to address(0), disabling all owner-only functions
    ///      Use with extreme caution. Ensure all fee tiers and settings are finalized.
    ///      After renouncing: no fee tier updates, no emergency withdrawals, no operator changes
    function renounceOwnership() external {
        if (msg.sender != OWNER) revert OnlyOwner();
        address previousOwner = OWNER;
        OWNER = address(0);
        emit OwnershipRenounced(previousOwner, block.timestamp);
    }

    /// @notice Set fee exemption for modules/extensions
    /// @dev Allows certain addresses to bypass fees (e.g., ModuleManager, burn modules)
    /// @param account Address to exempt or un-exempt
    /// @param exempt True to exempt from fees, false to remove exemption
    function setFeeExemption(address account, bool exempt) external {
        if (msg.sender != OWNER) revert OnlyOwner();
        if (account == address(0)) revert InvalidAddress();

        feeExempt[account] = exempt;
        emit FeeExemptionSet(account, exempt);
    }

    /// @notice Update strategy address to redirect fee flows
    /// @dev Owner only - allows upgrading to a new strategy contract without redeploying hook
    ///      IMPORTANT: Flush pending fees to old strategy before updating
    /// @param newStrategy Address of the new strategy contract
    function setStrategy(address newStrategy) external {
        if (msg.sender != OWNER) revert OnlyOwner();
        if (newStrategy == address(0)) revert InvalidStrategy();

        address oldStrategy = STRATEGY;
        STRATEGY = newStrategy;
        emit StrategyUpdated(oldStrategy, newStrategy);
    }

    /// @notice Update treasury address to redirect rake fees
    /// @dev Owner only - allows updating treasury without redeploying hook
    ///      IMPORTANT: Flush pending rake to old treasury before updating
    /// @param newTreasury Address of the new treasury
    function setTreasury(address newTreasury) external {
        if (msg.sender != OWNER) revert OnlyOwner();
        if (newTreasury == address(0)) revert InvalidTreasury();

        address oldTreasury = TREASURY;
        TREASURY = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                              PHASE 0 - FEE ACTIVATION                        */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Enable fees (toggleable, can be called multiple times)
    /// @dev Owner or operator can enable. Used for launch and after emergency pauses.
    function enableFees() external onlyOwnerOrOperator {
        if (feesEnabled) revert FeesAlreadyEnabled();

        feesEnabled = true;
        emit FeesEnabled(block.timestamp);
    }

    /// @notice Disable fees (emergency pause, toggleable)
    /// @dev Owner only - pauses all fee collection. Can be re-enabled later.
    ///      Use cases: market crisis, bug discovered, regulatory, promotional periods
    function disableFees() external {
        if (msg.sender != OWNER) revert OnlyOwner();
        if (!feesEnabled) revert FeesAlreadyDisabled();

        feesEnabled = false;
        emit FeesDisabled(block.timestamp);
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                          PHASE TRANSITIONS & FEE SPIKES                      */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Manually activate Phase 2 (Owner only)
    /// @dev Allows owner to transition from Phase 1 (50% flat) to Phase 2 (10-90% dynamic)
    ///      without waiting for strategy's first sale. Useful for:
    ///      - Skipping Phase 1 entirely at launch
    ///      - Testing Phase 2 functionality
    ///      - Emergency transition to lower base fees
    /// @param initialSpikeAmount ETH amount to trigger initial spike (0 for no spike, starts at 10% base)
    function activatePhase2(uint256 initialSpikeAmount) external {
        if (msg.sender != OWNER) revert OnlyOwner();
        if (phase2Activated) revert Phase2AlreadyActive();

        // Activate Phase 2 first (before spike trigger for safety)
        phase2Activated = true;

        // Optionally trigger initial spike if amount provided
        if (initialSpikeAmount > 0) {
            _triggerFeeSpike(initialSpikeAmount);
        }

        emit Phase2Activated(block.timestamp);
    }

    /// @notice Strategy calls this after FIRST successful sale (Phase 1 → Phase 2)
    /// @dev Automatic transition - strategy triggers this after first successful sale
    function notifyFirstSale(uint256 saleAmount) external {
        if (msg.sender != address(STRATEGY)) revert OnlyStrategy();
        if (phase2Activated) revert Phase2AlreadyActive();

        // Activate Phase 2 first (before spike trigger for safety)
        phase2Activated = true;

        // Trigger initial fee spike
        _triggerFeeSpike(saleAmount);

        emit FirstSaleExecuted(saleAmount, block.timestamp);
        emit Phase2Activated(block.timestamp);
    }

    /// @notice Trigger fee spike on subsequent sales
    function triggerFeeSpike(uint256 saleAmount) external {
        if (msg.sender != address(STRATEGY)) revert OnlyStrategy();
        if (!phase2Activated) revert Phase2NotActive();

        _triggerFeeSpike(saleAmount);
    }

    /// @notice Internal spike logic - determines tier and sets fee
    function _triggerFeeSpike(uint256 saleAmount) internal {
        // Use storage reference for gas optimization
        FeeSpike[10] storage tiers = feeSpikeTiers;
        uint256 len = tiers.length;

        // Find the appropriate tier (iterate from highest to lowest)
        for (uint256 i = len; i > 0; ) {
            unchecked {
                --i;
            } // Safe: i > 0 checked in loop condition
            FeeSpike memory tier = tiers[i];

            if (saleAmount >= tier.triggerAmount) {
                // Check current sell fee to avoid downgrading during active spike
                uint256 currentSellFee = getCurrentFee(false);

                // Only spike if new fee is higher than current
                if (tier.feePercent > currentSellFee) {
                    currentFeeSpike = tier.feePercent;
                    feeSpikeTriggerTime = block.timestamp;
                    feeDecayDuration = tier.decayHours * 1 hours;

                    emit FeeSpikeTriggered(
                        saleAmount,
                        tier.feePercent,
                        tier.decayHours
                    );
                }
                break;
            }
        }
    }

    /// @notice Calculate current dynamic fee with decay
    /// @dev Includes runtime cap at 90% (9000 BPS) as defense-in-depth safety measure
    function getCurrentFee(bool isBuy) public view returns (uint256) {
        uint256 fee;

        // Phase 1: Flat 50% fee
        if (!phase2Activated) {
            fee = PHASE1_FEE_BIPS;
        }
        // Phase 2: No active spike - return base fee
        else if (currentFeeSpike == 0) {
            fee = BASE_FEE_BIPS;
        }
        // Phase 2: Active spike with decay
        else {
            // Calculate time elapsed since spike
            uint256 elapsed = block.timestamp - feeSpikeTriggerTime;

            // Decay period complete - back to base
            if (elapsed >= feeDecayDuration) {
                fee = BASE_FEE_BIPS;
            } else {
                // Linear decay: currentSpike → baseFee over decay duration
                uint256 spikeIncrease = currentFeeSpike - BASE_FEE_BIPS;
                uint256 decayAmount = (spikeIncrease * elapsed) / feeDecayDuration;
                uint256 currentSellFee = currentFeeSpike - decayAmount;

                // SELLS: Full spike fee
                if (!isBuy) {
                    fee = currentSellFee;
                }
                // BUYS: Asymmetric fee - Base + 10% of spike increase
                // Example: If spike = 9000 bips (90%), buys pay:
                //   Base (1000) + 10% of (9000-1000) = 1000 + 800 = 1800 bips (18%)
                // This creates favorable conditions for buyers during high-fee periods
                else {
                    uint256 activeSpikeIncrease = currentSellFee - BASE_FEE_BIPS;
                    uint256 buyFeeIncrease = (activeSpikeIncrease * BUY_SPIKE_RATIO) /
                        TOTAL_BIPS;
                    fee = BASE_FEE_BIPS + buyFeeIncrease;
                }
            }
        }

        // Defense-in-depth: Runtime cap at 90% (protects against config errors or future bugs)
        if (fee > 9000) {
            fee = 9000;
        }

        return fee;
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                          FEE TIER MANAGEMENT (ADMIN)                         */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Update base fee (Phase 2 base fee when no spike active)
    /// @param newBaseFee New base fee in bips (e.g., 500 = 5%, 1000 = 10%)
    /// @dev Owner only - changes the floor fee that spikes decay back to
    ///      IMPORTANT: All existing tier feePercent values must be >= newBaseFee
    ///      Consider updating tiers first if lowering base fee below current minimums
    function setBaseFee(uint256 newBaseFee) external {
        if (msg.sender != OWNER) revert OnlyOwner();
        require(newBaseFee >= 100, "Base fee too low"); // Min 1%
        require(newBaseFee <= 1000, "Base fee too high"); // Max 10%
        
        uint256 oldBaseFee = BASE_FEE_BIPS;
        BASE_FEE_BIPS = uint128(newBaseFee);
        
        emit BaseFeeUpdated(oldBaseFee, newBaseFee);
    }

    /// @notice Update a single fee tier
    /// @param index Tier index (0-9)
    /// @param triggerAmount New ETH threshold
    /// @param feePercent New fee percentage in bips
    /// @param decayHours New decay duration in hours
    function updateFeeTier(
        uint256 index,
        uint256 triggerAmount,
        uint256 feePercent,
        uint256 decayHours
    ) external onlyOwnerOrOperator {
        require(index < 10, "Invalid tier index");
        require(triggerAmount > 0, "Zero threshold");
        require(feePercent <= 9000, "Fee too high"); // Max 90%
        require(feePercent >= BASE_FEE_BIPS, "Fee below base"); // Must be >= current base
        require(decayHours > 0 && decayHours <= 24, "Invalid decay");

        feeSpikeTiers[index] = FeeSpike({
            triggerAmount: triggerAmount,
            feePercent: feePercent,
            decayHours: decayHours
        });

        emit FeeTierUpdated(index, triggerAmount, feePercent, decayHours);
    }

    /// @notice Update all fee tiers at once
    /// @param newTiers Array of 10 new tier configurations
    function updateAllFeeTiers(
        FeeSpike[10] calldata newTiers
    ) external onlyOwnerOrOperator {
        for (uint256 i = 0; i < 10; i++) {
            require(newTiers[i].triggerAmount > 0, "Zero threshold");
            require(newTiers[i].feePercent <= 9000, "Fee too high");
            require(newTiers[i].feePercent >= BASE_FEE_BIPS, "Fee below base");
            require(
                newTiers[i].decayHours > 0 && newTiers[i].decayHours <= 24,
                "Invalid decay"
            );

            feeSpikeTiers[i] = newTiers[i];
        }

        emit AllFeeTiersUpdated();
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                              HOOK IMPLEMENTATION                             */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Called before swap to collect fees on BUYS (ETH → MEMS)
    /// @dev Takes dynamic fee from input when users buy MEMS tokens
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    )
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // ANTI-SNIPE: Block ALL public swaps until strategy trading is enabled
        // This prevents direct PoolManager.unlock() bypass attacks
        // Strategy itself can always swap (for buybacks), owner-controlled addresses can swap
        try IStrategy(STRATEGY).tradingEnabled() returns (bool tradingActive) {
            if (!tradingActive) {
                // Only allow strategy itself and fee-exempt addresses (modules) to swap
                if (sender != address(STRATEGY) && !feeExempt[sender]) {
                    revert TradingNotEnabled();
                }
            }
        } catch {
            // If strategy call fails, assume trading is disabled (fail-safe)
            if (sender != address(STRATEGY) && !feeExempt[sender]) {
                revert TradingNotEnabled();
            }
        }

        // Phase 0: No fees during bundle
        // Strategy buybacks and whitelisted modules bypass fees (no double taxation)
        if (!feesEnabled || sender == address(STRATEGY) || feeExempt[sender]) {
            return (
                IHooks.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                0
            );
        }

        // Only collect fee when PUBLIC users BUY MEMS (ETH → MEMS)
        // zeroForOne = true means currency0 (ETH) → currency1 (MEMS)
        if (params.zeroForOne) {
            // Only support exact input swaps (amountSpecified < 0)
            if (params.amountSpecified >= 0) revert ExactOutputNotSupported();

            // User is buying MEMS, take fee from their ETH input
            // Convert negative amountSpecified to positive uint256 for clarity
            uint256 ethInput = uint256(-params.amountSpecified);

            // Calculate dynamic fee
            uint256 buyFeeBips = getCurrentFee(true);
            uint256 totalFeeU256 = (ethInput * buyFeeBips) / TOTAL_BIPS;

            // Defensive check: ensure fee fits in uint128 (practically always true)
            require(totalFeeU256 <= type(uint128).max, "Fee overflow");
            uint128 totalFee = uint128(totalFeeU256);

            // Split 80/20 (ensure sum equals total by calculating rake as remainder)
            uint128 strategyFee = (totalFee * STRATEGY_BIPS) / TOTAL_BIPS;
            uint128 rakeFee = totalFee - strategyFee;

            // Take ETH fee from PoolManager
            POOL_MANAGER.take(key.currency0, address(this), totalFee);

            emit FeeCollected(
                key.currency0,
                totalFee,
                strategyFee,
                rakeFee,
                buyFeeBips
            );

            // Accumulate fees for later flush (no external calls during swap)
            _accumulateStrategyFees(strategyFee);
            _accumulateRake(rakeFee);

            // Return delta - user pays additional ETH as fee
            // Use SafeCast for type conversion safety
            BeforeSwapDelta delta = toBeforeSwapDelta(
                uint256(totalFee).toInt128(),
                0
            );
            return (IHooks.beforeSwap.selector, delta, 0);
        }

        // User selling MEMS → ETH: handled in afterSwap
        return (
            IHooks.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }

    /// @notice Called after swap to collect fees on SELLS (MEMS → ETH)
    /// @dev Takes dynamic fee from output when users sell MEMS tokens
    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        // ANTI-SNIPE: Block ALL public swaps until strategy trading is enabled
        // This prevents direct PoolManager.unlock() bypass attacks
        try IStrategy(STRATEGY).tradingEnabled() returns (bool tradingActive) {
            if (!tradingActive) {
                // Only allow strategy itself and fee-exempt addresses (modules) to swap
                if (sender != address(STRATEGY) && !feeExempt[sender]) {
                    revert TradingNotEnabled();
                }
            }
        } catch {
            // If strategy call fails, assume trading is disabled (fail-safe)
            if (sender != address(STRATEGY) && !feeExempt[sender]) {
                revert TradingNotEnabled();
            }
        }

        // Phase 0: No fees during bundle
        // Strategy buybacks and whitelisted modules bypass fees (no double taxation)
        if (!feesEnabled || sender == address(STRATEGY) || feeExempt[sender]) {
            return (IHooks.afterSwap.selector, 0);
        }

        // Only collect fee when PUBLIC users SELL MEMS (MEMS → ETH)
        // zeroForOne = false means currency1 (MEMS) → currency0 (ETH)
        if (!params.zeroForOne) {
            // Only support exact input swaps (amountSpecified < 0)
            if (params.amountSpecified >= 0) revert ExactOutputNotSupported();

            // User is selling MEMS, take fee from their ETH output
            int128 ethOutput = delta.amount0();

            // Verify ETH output is positive (safety check)
            require(ethOutput > 0, "Unexpected negative delta");

            // Convert to uint128 then uint256 for arithmetic
            uint128 ethOut128 = ethOutput.toUint128();
            uint256 ethOut = uint256(ethOut128);

            // Calculate dynamic fee
            uint256 sellFeeBips = getCurrentFee(false);
            uint256 totalFeeU256 = (ethOut * sellFeeBips) / TOTAL_BIPS;

            // Defensive check: ensure fee fits in uint128 (practically always true)
            require(totalFeeU256 <= type(uint128).max, "Fee overflow");
            uint128 totalFee = uint128(totalFeeU256);

            // Split 80/20 (ensure sum equals total by calculating rake as remainder)
            uint128 strategyFee = (totalFee * STRATEGY_BIPS) / TOTAL_BIPS;
            uint128 rakeFee = totalFee - strategyFee;

            // Take ETH fee from PoolManager
            POOL_MANAGER.take(key.currency0, address(this), totalFee);

            emit FeeCollected(
                key.currency0,
                totalFee,
                strategyFee,
                rakeFee,
                sellFeeBips
            );

            // Accumulate fees for later flush (no external calls during swap)
            _accumulateStrategyFees(strategyFee);
            _accumulateRake(rakeFee);

            // Return delta - user receives less ETH (use SafeCast)
            return (IHooks.afterSwap.selector, uint256(totalFee).toInt128());
        }

        // User buying MEMS → ETH: already handled in beforeSwap
        return (IHooks.afterSwap.selector, 0);
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                              FEE MANAGEMENT                                  */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Accumulate strategy fees (80% portion) - NO external calls during swap
    /// @dev Deferred settlement pattern: collect now, flush later (best practice for V4 hooks)
    function _accumulateStrategyFees(uint256 amount) internal {
        if (amount == 0) return;
        pendingStrategy += amount;
    }

    /// @notice Accumulate rake fees (20% portion) - NO external calls during swap
    /// @dev Deferred settlement pattern: collect now, flush later (best practice for V4 hooks)
    function _accumulateRake(uint256 amount) internal {
        if (amount == 0) return;
        pendingRake += amount;
    }

    /// @notice Flush accumulated strategy fees to MemeStrategy contract
    /// @dev Operator/Owner only - designed for automated keeper execution
    ///      External calls happen OUTSIDE swap path (keeps swaps deterministic & safe)
    function flushToStrategy() external onlyOwnerOrOperator {
        uint256 amt = pendingStrategy;
        if (amt == 0) return;

        // Reset before transfer (reentrancy guard)
        pendingStrategy = 0;

        // Try to send to strategy
        try IStrategy(STRATEGY).addFeesETH{value: amt}() {
            emit FeesFlushedToStrategy(amt);
        } catch {
            // Restore on failure
            pendingStrategy = amt;
            emit StrategyFlushFailed(amt);
        }
    }

    /// @notice Flush accumulated rake to treasury
    /// @dev Operator/Owner only - designed for automated keeper execution
    ///      External calls happen OUTSIDE swap path (keeps swaps deterministic & safe)
    function flushRake() external onlyOwnerOrOperator {
        uint256 amt = pendingRake;
        if (amt == 0) return;

        // Reset before transfer (reentrancy guard)
        pendingRake = 0;

        // Try to send to treasury with gas limit (protection against malicious treasury)
        (bool success, ) = TREASURY.call{value: amt, gas: 50000}("");

        if (!success) {
            // Restore on failure
            pendingRake = amt;
            emit RakeFlushFailed(amt);
            return;
        }

        emit RakeFlushed(TREASURY, amt);
    }

    /// @notice Flush all pending fees (strategy + rake) in one call
    /// @dev Convenience function for automated keepers
    function flushAllFees() external onlyOwnerOrOperator {
        // Flush strategy first (more important)
        if (pendingStrategy > 0) {
            uint256 stratAmt = pendingStrategy;
            pendingStrategy = 0;

            try IStrategy(STRATEGY).addFeesETH{value: stratAmt}() {
                emit FeesFlushedToStrategy(stratAmt);
            } catch {
                pendingStrategy = stratAmt;
                emit StrategyFlushFailed(stratAmt);
            }
        }

        // Then flush rake
        if (pendingRake > 0) {
            uint256 rakeAmt = pendingRake;
            pendingRake = 0;

            (bool success, ) = TREASURY.call{value: rakeAmt, gas: 50000}("");

            if (!success) {
                pendingRake = rakeAmt;
                emit RakeFlushFailed(rakeAmt);
            } else {
                emit RakeFlushed(TREASURY, rakeAmt);
            }
        }
    }

    /// @notice Get pending fee balances awaiting flush
    /// @dev Returns (pendingStrategy, pendingRake, totalInHook)
    function getPendingFees() external view returns (
        uint256 strategyPending,
        uint256 rakePending,
        uint256 totalBalance
    ) {
        return (pendingStrategy, pendingRake, address(this).balance);
    }

    /// @notice Emergency withdraw ETH from hook (owner only)
    /// @dev Use case: recover stuck ETH from failed deposits or manual sends
    /// @param to Recipient address
    /// @param amount Amount of ETH to withdraw
    function emergencyWithdrawETH(address to, uint256 amount) external {
        if (msg.sender != OWNER) revert OnlyOwner();
        if (to == address(0)) revert InvalidAddress();

        SafeTransferLib.safeTransferETH(to, amount);
        emit EmergencyWithdrawETH(to, amount);
    }

    /// @notice Hook can receive native ETH
    /// @dev Emits Received event for transparency and off-chain tracking
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                              VIEW FUNCTIONS                                  */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Get current phase information
    function getPhaseInfo()
        external
        view
        returns (uint8 phase, bool phase2Active, uint256 currentBaseFee)
    {
        phase = phase2Activated ? 2 : 1;
        phase2Active = phase2Activated;
        currentBaseFee = phase2Activated ? BASE_FEE_BIPS : PHASE1_FEE_BIPS;
    }

    /// @notice Get active spike information
    function getSpikeInfo()
        external
        view
        returns (
            bool isActive,
            uint256 currentSellFee,
            uint256 currentBuyFee,
            uint256 timeRemaining,
            uint256 decayProgress
        )
    {
        if (!phase2Activated || currentFeeSpike == 0) {
            return (false, BASE_FEE_BIPS, BASE_FEE_BIPS, 0, 100);
        }

        uint256 elapsed = block.timestamp - feeSpikeTriggerTime;

        if (elapsed >= feeDecayDuration) {
            return (false, BASE_FEE_BIPS, BASE_FEE_BIPS, 0, 100);
        }

        isActive = true;
        currentSellFee = getCurrentFee(false);
        currentBuyFee = getCurrentFee(true);
        timeRemaining = feeDecayDuration - elapsed;
        decayProgress = (elapsed * 100) / feeDecayDuration;
    }

    /// @notice Get tier information for ETH amount
    function getTierForAmount(
        uint256 ethAmount
    ) external view returns (uint256 feePercent, uint256 decayHours) {
        for (uint256 i = feeSpikeTiers.length; i > 0; i--) {
            FeeSpike memory tier = feeSpikeTiers[i - 1];
            if (ethAmount >= tier.triggerAmount) {
                return (tier.feePercent, tier.decayHours);
            }
        }
        // Below minimum tier
        return (BASE_FEE_BIPS, 0);
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                      IHOOKS INTERFACE - NOT IMPLEMENTED                      */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    function beforeInitialize(
        address,
        PoolKey calldata,
        uint160
    ) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterInitialize(
        address,
        PoolKey calldata,
        uint160,
        int24
    ) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
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

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
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

    // beforeSwap is implemented above

    function beforeDonate(
        address,
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterDonate(
        address,
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        revert HookNotImplemented();
    }
}
