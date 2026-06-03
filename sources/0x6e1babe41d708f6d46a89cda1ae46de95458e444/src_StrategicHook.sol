// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import "./Interfaces.sol";

/// @title StrategicHook - Uniswap V4 Hook for Strategic Reserve
/// @author Strategic Reserve (https://strategicreserve.fun/)
/// @notice This hook manages fee collection and distribution for Strategic Reserve pools on Uniswap V4
/// @dev Implements dynamic fee structure that decreases over time after deployment
contract StrategicHook is BaseHook, ReentrancyGuard {
    //
    //    _____ __             __             _
    //   / ___// /__________ _/ /____  ____ _(_)____
    //   \__ \/ __/ ___/ __ `/ __/ _ \/ __ `/ / ___/
    //  ___/ / /_/ /  / /_/ / /_/  __/ /_/ / / /__
    // /____/\__/_/   \__,_/\__/\___/\__, /_/\___/
    //    / __ \___  ________  _____/____/___
    //   / /_/ / _ \/ ___/ _ \/ ___/ | / / _ \
    //  / _, _/  __(__  )  __/ /   | |/ /  __/
    // /_/ |_|\___/____/\___/_/    |___/\___/

    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencySettler for Currency;
    using SafeCast for uint256;
    using SafeCast for int128;

    /* ═══════════════════════════════════════════════════ */
    /*                      CONSTANTS                      */
    /* ═══════════════════════════════════════════════════ */
    /// @notice Total basis points for percentage calculations
    uint128 private constant TOTAL_BIPS = 10000;
    /// @notice Maximum price limit for swaps
    uint160 private constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    /// @notice The StrategicFactory contract
    IStrategicFactory immutable strategicFactory;
    /// @notice The Uniswap V4 Pool Manager
    IPoolManager immutable manager;

    /* ═══════════════════════════════════════════════════ */
    /*                   STATE VARIABLES                   */
    /* ═══════════════════════════════════════════════════ */
    /// @notice Default buy fee floor (10%) - configurable between 4-10%
    uint128 public defaultFeeBuy = 1000;
    /// @notice Default sell fee floor (10%) - configurable between 4-10%
    uint128 public defaultFeeSell = 1000;
    /// @notice Starting buy fee rate - decreases over time
    uint128 public startingBuyFee = 8000;
    /// @notice Mapping of reserve addresses to their blocks per 1% fee drop
    mapping(address => uint128) public blocksPerDrop;
    /// @notice Default blocks per 1% fee drop for newly deployed reserves (720 = 7d for 70% decay)
    uint128 public defaultBlocksPerDrop = 720;
    /// @notice When true, default fees are permanently locked and cannot be altered
    bool public defaultFeesLocked;
    /// @notice Mapping of reserve addresses to their deployment block numbers
    mapping(address => uint256) public deploymentBlock;
    /// @notice Mapping of reserve addresses to custom fee recipient addresses
    mapping(address => address) public feeAddressToReserve;
    /// @notice The first reserve deployed (PUNKSR) - receives all protocol revenue
    address public v1Reserve;
    /// @notice Default fee for newly deployed reserves (in bips, default 1600 = 16%)
    uint128 public defaultReserveVaultFee = 1000;

    /* ═══════════════════════════════════════════════════ */
    /*                    CUSTOM ERRORS                    */
    /* ═══════════════════════════════════════════════════ */
    /// @notice Caller is not an authorized StrategicReserve contract
    error NotAuthorizedReserve();
    /// @notice Caller is not authorized for this operation
    error NotAuthorized();
    /// @notice Restrict ExactOutput swaps
    error ExactOutputNotAllowed();
    /// @notice V1 reserve already set (can only be set once)
    error V1ReserveAlreadySet();
    /// @notice Invalid V1 reserve address
    error InvalidV1Reserve();
    /// @notice Invalid default fee (must be 400-1000 bips / 4-10%)
    error InvalidDefaultFee();
    /// @notice Default fees have been permanently locked
    error DefaultFeesLocked();
    /// @notice Invalid starting buy fee (must be >= defaultFeeBuy and <= 9980)
    error InvalidStartingFee();

    /* ═══════════════════════════════════════════════════ */
    /*                    CUSTOM EVENTS                    */
    /* ═══════════════════════════════════════════════════ */
    /// @notice Emitted when fees are collected from a swap
    event HookFee(bytes32 indexed id, address indexed sender, uint128 feeAmount0, uint128 feeAmount1);
    /// @notice Emitted when a trade occurs in a StrategicReserve pool
    event Trade(address indexed reserve, uint160 sqrtPriceX96, int128 ethAmount, int128 tokenAmount);
    /// @notice Emitted when starting buy fee is updated
    event StartingBuyFeeUpdated(uint128 oldFee, uint128 newFee);
    /// @notice Emitted when default reserve vault fee is updated
    event DefaultReserveVaultFeeUpdated(uint128 oldFee, uint128 newFee);
    /// @notice Emitted when default buy/sell fees are updated
    event DefaultFeeUpdated(uint128 oldBuy, uint128 newBuy, uint128 oldSell, uint128 newSell);

    /* ═══════════════════════════════════════════════════ */
    /*                     CONSTRUCTOR                     */
    /* ═══════════════════════════════════════════════════ */
    /// @notice Constructor initializes the hook with required dependencies
    /// @param _poolManager The Uniswap V4 Pool Manager interface
    /// @param _strategicFactory The StrategicFactory contract
    /// @dev Sets up immutable references to core contracts
    constructor(
        IPoolManager _poolManager,
        IStrategicFactory _strategicFactory
    ) BaseHook(_poolManager) {
        manager = _poolManager;
        strategicFactory = _strategicFactory;
    }

    /* ═══════════════════════════════════════════════════ */
    /*                      MODIFIERS                      */
    /* ═══════════════════════════════════════════════════ */
    /// @notice Restricts function access to the factory contract only
    modifier onlyFactory() {
        if (msg.sender != address(strategicFactory)) revert NotAuthorized();
        _;
    }

    /* ═══════════════════════════════════════════════════ */
    /*                     FUNCTIONS                       */
    /* ═══════════════════════════════════════════════════ */
    /// @notice Updates the fee address for a reserve
    /// @param reserve The StrategicReserve contract address
    /// @param destination New address to receive fees for this reserve
    /// @dev Only callable by the factory contract. First-time setting is immediate, changes require 30-day timelock via Reserve.
    function updateFeeAddress(address reserve, address destination) external onlyFactory {
        // First-time setting (address not yet set) → immediate, no timelock
        if (feeAddressToReserve[reserve] == address(0)) {
            feeAddressToReserve[reserve] = destination;
            return;
        }

        // Changing existing address → enforce 30-day timelock via Reserve
        if (IStrategicReserve(reserve).processVaultChange(feeAddressToReserve[reserve], destination)) {
            feeAddressToReserve[reserve] = destination;
        }
    }

    /// @notice Sets the V1 reserve address (can only be called once by factory)
    /// @param _v1Reserve Address of the first deployed reserve (PUNKSR)
    /// @dev Only callable by factory, only once during first reserve launch
    /// @dev V1 configuration (vault fee 20%) is managed in Reserve contract by deployment script
    function setV1Reserve(address _v1Reserve) external onlyFactory {
        if (v1Reserve != address(0)) revert V1ReserveAlreadySet();
        if (_v1Reserve == address(0)) revert InvalidV1Reserve();

        // v1Reserve = V1's Strategic Reserve contract address
        v1Reserve = _v1Reserve;
    }

    /// @notice Updates the starting buy fee for new reserves
    /// @param _newFee New starting buy fee in basis points
    /// @dev Only callable by factory contract. Must be >= defaultFeeBuy and <= 9990
    function setStartingBuyFee(uint128 _newFee) external onlyFactory {
        if (_newFee < defaultFeeBuy || _newFee > 9900) revert InvalidStartingFee();
        uint128 oldFee = startingBuyFee;
        startingBuyFee = _newFee;
        emit StartingBuyFeeUpdated(oldFee, _newFee);
    }

    /// @notice Updates the default buy and sell fee floors
    /// @param _buyFee New default buy fee floor in basis points
    /// @param _sellFee New default sell fee floor in basis points
    /// @dev Only callable by factory contract. Both fees must be 400-1000 bips (4-10%)
    function setDefaultFee(uint128 _buyFee, uint128 _sellFee) external onlyFactory {
        if (defaultFeesLocked) revert DefaultFeesLocked();
        if (_buyFee < 400 || _buyFee > 1000) revert InvalidDefaultFee();
        if (_sellFee < 400 || _sellFee > 1000) revert InvalidDefaultFee();

        uint128 oldBuy = defaultFeeBuy;
        uint128 oldSell = defaultFeeSell;

        defaultFeeBuy = _buyFee;
        defaultFeeSell = _sellFee;

        emit DefaultFeeUpdated(oldBuy, _buyFee, oldSell, _sellFee);
    }

    /// @notice Permanently locks default fees, preventing any future changes
    /// @dev Only callable by factory contract. This is irreversible - once locked, fees cannot be changed ever again
    function lockDefaultFees() external onlyFactory {
        if (defaultFeesLocked) revert DefaultFeesLocked();
        defaultFeesLocked = true;
    }

    /// @notice Sets the default vault fee for newly deployed reserves
    /// @param _feeBips New default reserve vault fee in basis points
    /// @dev Only callable by factory contract. Must be between 1000-2000 bips (10-20%). Does not affect existing reserves, only future deployments.
    function setDefaultReserveVaultFee(uint128 _feeBips) external onlyFactory {
        require(_feeBips >= 1000 && _feeBips <= 2000, "Fee must be 10-20%");
        uint128 oldFee = defaultReserveVaultFee;
        defaultReserveVaultFee = _feeBips;
        emit DefaultReserveVaultFeeUpdated(oldFee, _feeBips);
    }

    /// @notice Sets the default blocks per drop for newly deployed reserves
    /// @param _blocks Number of blocks per 1% fee reduction
    /// @dev Only callable by factory contract. Must be between 1-3100 blocks (max = 30 days decay). Does not affect existing reserves, only future deployments.
    function setDefaultBlocksPerDrop(uint128 _blocks) external onlyFactory {
        require(_blocks >= 1 && _blocks <= 3100, "Invalid blocks per drop"); // 3100 = ~30 days for 70% decay
        defaultBlocksPerDrop = _blocks;
    }

    /// @notice Sets the blocks per drop for a specific reserve
    /// @param reserve The Strategic Reserve address
    /// @param _blocks Number of blocks per 1% fee reduction
    /// @dev Only callable by factory contract. Must be between 1-3100 blocks (max = 30 days). Affects ongoing decay for this reserve.
    function setBlocksPerDrop(address reserve, uint128 _blocks) external onlyFactory {
        require(_blocks >= 1 && _blocks <= 3100, "Invalid blocks per drop"); // 3100 = ~30 days for 70% decay
        blocksPerDrop[reserve] = _blocks;
    }

    /// @notice Process fees directly - distributes immediately
    /// @param reserve The Strategic Reserve address
    /// @param feeAmount Amount of ETH fees to distribute
    /// @dev 80% reserve + configurable% reserve vault (from Reserve contract) + remaining split 50/50 between V1 Reserve & V1 Vault
    /// @dev V1 should be set to 2000 bips (20%) to keep all vault fees (v1Split becomes 0)
    /// @dev Safety: Falls back to 10% vault (1000 bips) if Reserve read fails to prevent swap blocking
    function _processFees(address reserve, uint256 feeAmount) internal {
        if (feeAmount == 0) return;

        // 80% always goes to the reserve contract for NFT purchases
        uint256 depositAmount = (feeAmount * 80) / 100;

        // Fallback: If reserve is broken/destroyed, send to Factory for PUNKSR buybacks
        try IStrategicReserve(reserve).addFees{value: depositAmount}() {
            // Success - normal operation
        } catch {
            // Reserve broken - send to Factory as safety net
            SafeTransferLib.forceSafeTransferETH(address(strategicFactory), depositAmount);
        }

        // Remaining 20% split based on reserveVaultFee + communityFee (read from Reserve with fallback)
        uint256 remaining = feeAmount - depositAmount;
        uint128 vaultFee;
        uint128 communityFeeAmt;
        address communityAddress;

        // Try to read vault fee from Reserve, fallback to 10% (1000 bips) if fails
        try IStrategicReserve(reserve).reserveVaultFee() returns (uint128 fee) {
            vaultFee = fee;
        } catch {
            // Fallback: 10% vault
            vaultFee = 1000;
        }

        // Try to read community fee from Reserve, fallback to 0 if fails
        try IStrategicReserve(reserve).communityFee() returns (uint128 fee) {
            communityFeeAmt = fee;
        } catch {
            // Fallback: no community fee
            communityFeeAmt = 0;
        }

        // Try to read community address from Reserve, fallback to address(0) if fails
        try IStrategicReserve(reserve).communityAddr() returns (address addr) {
            communityAddress = addr;
        } catch {
            // Fallback: no community address
            communityAddress = address(0);
        }

        uint256 reserveVaultAmount = (feeAmount * vaultFee) / 10000;
        uint256 communityAmount = (feeAmount * communityFeeAmt) / 10000;
        uint256 v1Split = remaining - reserveVaultAmount - communityAmount;

        // Process revenue sharing with V1 only if there's something to share
        if (v1Split > 0) {
            uint256 v1ReserveAmount = v1Split / 2;
            uint256 v1VaultAmount = v1Split - v1ReserveAmount;

            // Fallback: If V1 reserve is broken, send to Factory for PUNKSR buybacks
            try IStrategicReserve(v1Reserve).addFees{value: v1ReserveAmount}() {
                // Success - normal operation
            } catch {
                // Edge case: V1 can't receive fees - send to Factory as fallback
                SafeTransferLib.forceSafeTransferETH(address(strategicFactory), v1ReserveAmount);
            }
            SafeTransferLib.forceSafeTransferETH(feeAddressToReserve[v1Reserve], v1VaultAmount);
        }

        // Transfer to reserve's vault
        SafeTransferLib.forceSafeTransferETH(feeAddressToReserve[reserve], reserveVaultAmount);

        // Transfer to community address (if set and non-zero)
        if (communityAmount > 0 && communityAddress != address(0)) {
            SafeTransferLib.forceSafeTransferETH(communityAddress, communityAmount);
        }
    }

    /// @notice Calculates current fee based on deployment block and swap direction
    /// @param reserve The Strategic Reserve address
    /// @param isBuying True if buying tokens (ETH -> tokens), false if selling
    /// @return Current fee in basis points
    /// @dev Buy fees decrease over time from startingBuyFee to defaultFeeBuy, sell fees are constant defaultFeeSell
    function calculateFee(address reserve, bool isBuying) public view returns (uint128) {
        if (!isBuying) return defaultFeeSell;

        uint256 deployedAt = deploymentBlock[reserve];
        if (deployedAt == 0) return defaultFeeBuy;

        uint256 blocksPassed = block.number - deployedAt;
        uint256 feeReductions = (blocksPassed / blocksPerDrop[reserve]) * 100; // bips to subtract

        uint256 maxReducible = startingBuyFee - defaultFeeBuy; // assumes invariant holds
        if (feeReductions >= maxReducible) return defaultFeeBuy;

        return uint128(startingBuyFee - feeReductions);
    }

    /// @notice Returns the hook's permissions for the Uniswap V4 pool
    /// @return Hooks.Permissions struct indicating which hooks are enabled
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
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

    /// @notice Validates initialization of a new pool
    /// @param key The pool key containing currency pair and hook information
    /// @return Selector indicating successful hook execution
    /// @dev Only allows ETH/token pools and validates call is from StrategicFactory
    function _beforeInitialize(address, PoolKey calldata key, uint160) internal override returns (bytes4) {
        require(key.currency0.isAddressZero(), "Only ETH/token pools are supported");
        // Ensure the call is coming from StrategicFactory
        if (!strategicFactory.loadingLiquidity()) {
            revert NotAuthorizedReserve();
        }

        // Get reserve address
        address reserveAddr = Currency.unwrap(key.currency1);
        deploymentBlock[reserveAddr] = block.number;
        blocksPerDrop[reserveAddr] = defaultBlocksPerDrop;

        // Vault already deployed by Factory and fee address set before _loadLiquidity()
        // Reserve reads default vault fee from Hook during its own initialize()
        return BaseHook.beforeInitialize.selector;
    }

    /// @notice Validates liquidity addition to a pool
    /// @param key The pool key containing currency pair information
    /// @param delta The balance changes from the liquidity addition
    /// @return Hook selector and zero delta
    /// @dev Only allows liquidity addition during factory loading, sets transfer allowance
    function _afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        // Ensure the call is coming from StrategicFactory
        if (!strategicFactory.loadingLiquidity()) {
            revert NotAuthorizedReserve();
        } else {
            // we are loading liquidity so admit a transfer allowance
            // safe casting, liquidity additions are -values
            IStrategicReserve(Currency.unwrap(key.currency1)).increaseTransferAllowance(uint256(int256(-delta.amount1())));
        }
        return (BaseHook.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /// @notice Processes swap events and takes the swap fee
    /// @param sender The address initiating the call (router)
    /// @param key The pool key containing token pair and fee information
    /// @param params Swap parameters including direction and amount
    /// @param delta Balance changes resulting from the swap
    /// @return Hook selector and fee amount taken
    /// @dev Calculates dynamic fees, takes fee from swap, and distributes to recipients
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        // Restrict Exact Out
        if (params.amountSpecified > 0) {
            revert ExactOutputNotAllowed();
        }

        // Calculate fee based on the swap amount
        bool specifiedTokenIs0 = (params.amountSpecified < 0 == params.zeroForOne);
        (Currency feeCurrency, int128 swapAmount) =
            (specifiedTokenIs0) ? (key.currency1, delta.amount1()) : (key.currency0, delta.amount0());

        if (swapAmount < 0) swapAmount = -swapAmount;

        bool ethFee = Currency.unwrap(feeCurrency) == address(0);
        address reserve = Currency.unwrap(key.currency1);

        uint128 currentFee = calculateFee(reserve, params.zeroForOne);
        uint256 feeAmount = uint128(swapAmount) * currentFee / TOTAL_BIPS;

        // regardless if NFTSTR is inbound or outbound from PoolManager, we need to set the transfer allowance
        uint256 reserveAmountToTransfer =
            delta.amount1() < 0 ? uint256(int256(-delta.amount1())) : uint256(int256(delta.amount1()));

        if (feeAmount == 0) {
            IStrategicReserve(reserve).increaseTransferAllowance(reserveAmountToTransfer);
            return (BaseHook.afterSwap.selector, 0);
        }

        // account for "fees-in-NFTSTR" for the transfer allowance
        // for exact inputs (ETH --> ??? NFTSTR) the fee is skimmed from delta.amount1() but its transferred to the hook
        reserveAmountToTransfer += (feeCurrency == key.currency1) ? feeAmount : 0;

        // for exact outputs because we are taking a surplus fee to the hook and then swapping again
        // i.e. PoolManager --feeAmount--> Hook --feeAmount--> PoolManager
        reserveAmountToTransfer += (feeCurrency == key.currency1 && 0 < params.amountSpecified) ? feeAmount * 2 : 0;

        IStrategicReserve(reserve).increaseTransferAllowance(reserveAmountToTransfer);

        manager.take(feeCurrency, address(this), feeAmount);

        // Emit the HookFee event, after taking the fee
        emit HookFee(
            PoolId.unwrap(key.toId()), sender, ethFee ? uint128(feeAmount) : 0, ethFee ? 0 : uint128(feeAmount)
        );

        // Handle fee distribution based on swap direction
        if (!ethFee) {
            // BUY swap: fee is in tokens, swap to ETH
            uint256 feeInETH = _swapToEth(key, feeAmount);
            _processFees(reserve, feeInETH);
        } else {
            // SELL swap: fee is already in ETH
            _processFees(reserve, feeAmount);
        }

        // Get current price and emit
        emit Trade(reserve, _getCurrentPrice(key), delta.amount0(), delta.amount1());

        return (BaseHook.afterSwap.selector, feeAmount.toInt128());
    }

    /// @notice Swaps tokens to ETH for fee processing
    /// @param key The pool key for the swap
    /// @param amount The amount of tokens to swap
    /// @return The amount of ETH received from the swap
    /// @dev Internal function to convert token fees to ETH before distribution
    function _swapToEth(PoolKey memory key, uint256 amount) internal returns (uint256) {
        uint256 ethBefore = address(this).balance;

        BalanceDelta delta = manager.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: -int256(amount), sqrtPriceLimitX96: MAX_PRICE_LIMIT}),
            bytes("")
        );

        // Handle token settlements, it's ALWAYS a oneForZero swap
        key.currency1.settle(poolManager, address(this), uint256(int256(-delta.amount1())), false);
        key.currency0.take(poolManager, address(this), uint256(int256(delta.amount0())), false);

        return address(this).balance - ethBefore;
    }

    /// @notice Gets the current price of a token pair from the pool
    /// @param key The pool key containing the token pair and pool parameters
    /// @return The current sqrtPriceX96 from slot0
    /// @dev Reads the current price from the pool's slot0 storage
    function _getCurrentPrice(PoolKey calldata key) internal view returns (uint160) {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        return sqrtPriceX96;
    }

    /// @notice Allows the contract to receive ETH
    receive() external payable {}
}
