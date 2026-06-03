// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TaxHook
 * @notice A Uniswap V4 hook that applies a tax on swaps for a specific token
 * and redirects it to both team and dev beneficiaries
 */
contract TaxHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;

    // Tax rate in basis points (1/100 of a percent)
    // 100 = 1%, 500 = 5%, etc.
    uint16 public constant TAX_RATE_DENOMINATOR = 10000;
    
    // Flag to tell Uniswap to use the returned fee
    uint24 public constant LP_FEE_OVERRIDE_FLAG = 0x400000; // 23rd bit set
    
    // Fee override value for zero LP fees 
    uint24 public constant FEE_OVERRIDE = LP_FEE_OVERRIDE_FLAG; // 0 fee with override flag
    
    /**
     * @notice Override LP fees explanation
     * When returning a fee from beforeSwap:
     * 1. The 23rd bit (0x400000) tells Uniswap to use the returned fee value
     * 2. Setting the value to ZERO_LP_FEE means users pay 0% LP fees
     * 3. Only taxes specified by the hook will be collected
     * 
     * This allows tokens to have completely custom fee structures
     * without any of the standard Uniswap LP fees.
     */

    // Address of the TokenLauncher contract
    address public launcherAddress;
    
    // The token that will be taxed in all pools
    address public boomToken;

    // Structure to track tax collection and withdrawal
    struct TaxInfo {
        uint256 collected;
        uint256 withdrawn;
    }

    // Global team tax tracking
    TaxInfo public globalTeamTaxInfo;

    // Global team tax rate in basis points
    uint16 public teamTaxBps;

    // Structure to store tax configuration per pool
    struct TaxConfig {
        bool enabled;        // Whether tax is enabled for this pool
        bool taxToken0;      // Whether to tax token0 (if false, taxes token1)
        uint16 devTaxBps;    // Dev tax rate in basis points (e.g., 100 = 1%)
        address devAddress;  // Address of the dev to receive the tax
    }

    // Mapping from pool ID to its tax configuration
    mapping(PoolId => TaxConfig) public taxConfigs;
    
    // Mapping from dev address to tax info (cumulative across all tokens)
    mapping(address => TaxInfo) public devTaxInfo;

    // Event emitted when tax is collected
    event TaxCollected(
        PoolId indexed poolId,
        address indexed teamAddress,
        address indexed devAddress,
        address tokenAddress,
        uint256 teamTaxAmount,
        uint256 devTaxAmount,
        bool isInflow
    );

    // Event emitted when a pool's tax configuration is set
    event TaxConfigSet(
        PoolId indexed poolId,
        bool enabled,
        bool taxToken0,
        uint16 devTaxBps,
        address devAddress
    );
    
    // Event emitted when team tax rate is updated
    event TeamTaxUpdated(uint16 teamTaxBps);
    
    // Event emitted when taxes are withdrawn
    event TaxWithdrawn(
        address indexed beneficiary,
        address indexed token,
        uint256 amount,
        bool isTeamTax
    );

    // Event emitted when launcher address is set
    event LauncherAddressSet(address launcherAddress);

    constructor(
        IPoolManager _poolManager, 
        address _owner,
        address _boomToken
    ) BaseHook(_poolManager) Ownable(_owner) {
        require(_boomToken != address(0), "TaxHook: Invalid boom token address");
        teamTaxBps = 100; // Initialize team tax rate to 1%
        boomToken = _boomToken;
    }

    /**
     * @notice Set the launcher address
     * @param _launcherAddress Address of the TokenLauncher contract
     */
    function setLauncherAddress(address _launcherAddress) external onlyOwner {
        require(_launcherAddress != address(0), "TaxHook: Invalid launcher address");
        launcherAddress = _launcherAddress;
        emit LauncherAddressSet(_launcherAddress);
    }

    /**
     * @notice Modifier to check if caller is owner or launcher
     */
    modifier onlyOwnerOrLauncher() {
        require(msg.sender == owner() || msg.sender == launcherAddress, "TaxHook: Only owner or launcher");
        _;
    }

    /**
     * @notice Set the global team tax rate
     * @param _teamTaxBps Team tax rate in basis points
     */
    function setTeamTaxRate(uint16 _teamTaxBps) external onlyOwner {
        require(_teamTaxBps <= TAX_RATE_DENOMINATOR / 10, "TaxHook: Tax rate too high"); // Max 10%
        teamTaxBps = _teamTaxBps;
        emit TeamTaxUpdated(_teamTaxBps);
    }

    /**
     * @notice Set up tax configuration for a pool
     * @param key The pool key
     * @param enabled Whether tax is enabled for this pool
     * @param taxToken0 Whether to tax token0 (if false, taxes token1)
     * @param devTaxBps Dev tax rate in basis points (e.g., 100 = 1%)
     * @param devAddress Address of the dev to receive the tax
     */
    function setTaxConfig(
        PoolKey calldata key,
        bool enabled,
        bool taxToken0,
        uint16 devTaxBps,
        address devAddress
    ) external onlyOwnerOrLauncher {
        require(devTaxBps <= TAX_RATE_DENOMINATOR / 10, "TaxHook: Tax rate too high"); // Max 10%
        require(devAddress != address(0), "TaxHook: Invalid dev address");
        
        // Verify that the indicated token to tax is boomToken
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        address taxTokenAddress = taxToken0 ? token0 : token1;
        
        require(taxTokenAddress == boomToken, "TaxHook: Can only tax boomToken");

        PoolId poolId = key.toId();
        TaxConfig storage config = taxConfigs[poolId];
        
        config.enabled = enabled;
        config.taxToken0 = taxToken0;
        config.devTaxBps = devTaxBps;
        config.devAddress = devAddress;
        
        // If we're changing configuration, don't reset the collected/withdrawn amounts

        emit TaxConfigSet(poolId, enabled, taxToken0, devTaxBps, devAddress);
    }

    /**
     * @notice Define the hook permissions
     * @return Hooks.Permissions The hook's permissions
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,  // Using beforeSwap to tax inflows
            afterSwap: true,   // Using afterSwap to tax outflows
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true, // Now enabling this to return a delta in beforeSwap
            afterSwapReturnDelta: true,  // Now enabling this to return a delta in afterSwap
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @notice Calculate tax amount based on value and tax rate
     * @param value The value to calculate tax on
     * @param taxRateBps The tax rate in basis points
     * @return taxAmount The calculated tax amount
     */
    function _calculateTax(uint256 value, uint16 taxRateBps) internal pure returns (uint256) {
        return (value * taxRateBps) / TAX_RATE_DENOMINATOR;
    }

    /**
     * @notice Hook called before a swap to tax inflows
     * @param sender The address that initiated the swap
     * @param key The pool key
     * @param params The swap parameters
     * @param data Additional data passed to the hook
     * @return selector The function selector
     * @return delta Any delta to apply
     * @return gasLimit The gas limit for the swap
     */
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata data
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // Initialize with default values
        BeforeSwapDelta deltaOut = BeforeSwapDeltaLibrary.ZERO_DELTA;
        
        PoolId poolId = key.toId();
        TaxConfig storage config = taxConfigs[poolId];
        
        // Skip if tax is not enabled for this pool
        if (!config.enabled) {
            return (BaseHook.beforeSwap.selector, deltaOut, FEE_OVERRIDE);
        }
        
        // Determine which token to tax
        Currency taxToken = config.taxToken0 ? key.currency0 : key.currency1;
        address tokenAddress = Currency.unwrap(taxToken);
        
        // Determine if the taxed token is being used as an input in this swap
        bool isTaxedTokenInput = (config.taxToken0 && params.zeroForOne) || 
                                (!config.taxToken0 && !params.zeroForOne);
        
        // Only apply tax in beforeSwap if:
        // 1. The taxed token is being provided as input (user is selling the taxed token)
        // 2. This is an exact-input swap (amountSpecified < 0)
        if (isTaxedTokenInput && params.amountSpecified < 0) {
            // Calculate absolute swap amount 
            uint256 absAmount = uint256(-params.amountSpecified);
            
            // Calculate both team and dev taxes
            uint256 teamTaxAmount = _calculateTax(absAmount, teamTaxBps);
            uint256 devTaxAmount = _calculateTax(absAmount, config.devTaxBps);
            uint256 totalTaxAmount = teamTaxAmount + devTaxAmount;
            
            if (totalTaxAmount > 0) {
                // Take the total tax from the pool
                poolManager.take(taxToken, address(this), totalTaxAmount);
                
                // Return a POSITIVE delta to balance out the debt created by take()
                deltaOut = toBeforeSwapDelta(int128(int256(totalTaxAmount)), 0);
                
                // Track team tax globally
                if (teamTaxAmount > 0) {
                    globalTeamTaxInfo.collected += teamTaxAmount;
                }
                
                // Track dev tax cumulatively
                if (devTaxAmount > 0) {
                    devTaxInfo[config.devAddress].collected += devTaxAmount;
                }
                
                // Emit single event with both tax amounts
                emit TaxCollected(
                    poolId, 
                    owner(), 
                    config.devAddress, 
                    tokenAddress, 
                    teamTaxAmount, 
                    devTaxAmount, 
                    true
                );
            }
        }

        return (BaseHook.beforeSwap.selector, deltaOut, FEE_OVERRIDE);
    }

    /**
     * @notice Hook called after a swap to tax outflows
     * @param sender The address that initiated the swap
     * @param key The pool key
     * @param params The swap parameters
     * @param delta The balance delta from the swap
     * @param data Additional data passed to the hook
     * @return selector The function selector
     * @return afterDelta Any additional amount to withdraw
     */
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) internal override returns (bytes4, int128) {
        // Default value for afterDelta
        int128 afterDelta = 0;
        
        PoolId poolId = key.toId();
        TaxConfig storage config = taxConfigs[poolId];

        // Skip if tax is not enabled for this pool
        if (!config.enabled) {
            return (BaseHook.afterSwap.selector, afterDelta);
        }

        // Determine which token to tax
        Currency taxToken = config.taxToken0 ? key.currency0 : key.currency1;
        address tokenAddress = Currency.unwrap(taxToken);

        int128 relevantDelta = config.taxToken0 ? delta.amount0() : delta.amount1();

        // Determine if the taxed token is being received as output in this swap
        bool isTaxedTokenOutput = (config.taxToken0 && !params.zeroForOne) || 
                                 (!config.taxToken0 && params.zeroForOne);

        // Only apply tax in afterSwap if:
        // 1. The taxed token is being received as output (user is buying the taxed token)
        // 2. The delta shows the token is flowing out of the pool (positive delta)
        if (isTaxedTokenOutput && relevantDelta > 0) {
            // Calculate tax amounts
            uint256 absAmount = uint256(int256(relevantDelta));
            uint256 teamTaxAmount = _calculateTax(absAmount, teamTaxBps);
            uint256 devTaxAmount = _calculateTax(absAmount, config.devTaxBps);
            uint256 totalTaxAmount = teamTaxAmount + devTaxAmount;

            if (totalTaxAmount > 0) {
                // Take the tax from the pool
                poolManager.take(taxToken, address(this), totalTaxAmount);
                
                // Return a POSITIVE delta to balance out the debt created by take()
                afterDelta = int128(int256(totalTaxAmount));
                
                // Track team tax globally
                if (teamTaxAmount > 0) {
                    globalTeamTaxInfo.collected += teamTaxAmount;
                }
                
                // Track dev tax cumulatively
                if (devTaxAmount > 0) {
                    devTaxInfo[config.devAddress].collected += devTaxAmount;
                }
                
                // Emit single event with both tax amounts
                emit TaxCollected(
                    poolId, 
                    owner(), 
                    config.devAddress, 
                    tokenAddress, 
                    teamTaxAmount, 
                    devTaxAmount, 
                    false
                );
            }
        }

        return (BaseHook.afterSwap.selector, afterDelta);
    }

    // Required receive function to handle ETH transfers
    receive() external payable {}

    /**
     * @notice Get the amount of dev tax collected and withdrawn
     * @param dev The developer address
     * @return collected Amount of dev tax collected
     * @return withdrawn Amount of dev tax withdrawn
     */
    function getDevTaxInfo(address dev) external view returns (uint256 collected, uint256 withdrawn) {
        TaxInfo memory info = devTaxInfo[dev];
        return (info.collected, info.withdrawn);
    }
    
    /**
     * @notice Get the global team tax info
     * @return collected Total amount of team tax collected across all tokens
     * @return withdrawn Total amount of team tax withdrawn
     */
    function getGlobalTeamTaxInfo() external view returns (uint256 collected, uint256 withdrawn) {
        return (globalTeamTaxInfo.collected, globalTeamTaxInfo.withdrawn);
    }

    /**
     * @notice Withdraws accumulated team taxes for the boom token
     */
    function withdrawTeamTax() external onlyOwner {
        // Calculate unwithdrawn amount
        uint256 unwithdrawnTotal = globalTeamTaxInfo.collected - globalTeamTaxInfo.withdrawn;
        require(unwithdrawnTotal > 0, "TaxHook: No team taxes to withdraw");
        
        // Check if boom token has any balance
        uint256 balance = IERC20(boomToken).balanceOf(address(this));
        require(balance >= unwithdrawnTotal, "TaxHook: Insufficient balance to withdraw");
        
        // Update global withdrawn amount
        globalTeamTaxInfo.withdrawn += unwithdrawnTotal;
        
        // Transfer tokens to owner
        bool success = IERC20(boomToken).transfer(owner(), unwithdrawnTotal);
        require(success, "TaxHook: ERC20 transfer failed");
        emit TaxWithdrawn(owner(), boomToken, unwithdrawnTotal, true);
    }

    function withdrawEth() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "TaxHook: ETH transfer failed");
    }

    /**
     * @notice Withdraws accumulated dev taxes for the boom token
     */
    function withdrawDevTax() external {
        TaxInfo storage info = devTaxInfo[msg.sender];
        uint256 unwithdrawnTotal = info.collected - info.withdrawn;
        require(unwithdrawnTotal > 0, "TaxHook: No taxes to withdraw");
        
        // Check actual token balance
        uint256 balance = IERC20(boomToken).balanceOf(address(this));
        require(balance >= unwithdrawnTotal, "TaxHook: Insufficient balance to withdraw");

        // Update the withdrawn amount
        info.withdrawn += unwithdrawnTotal;

        // Transfer the token
        bool success = IERC20(boomToken).transfer(msg.sender, unwithdrawnTotal);
        require(success, "TaxHook: ERC20 transfer failed");        
        
        emit TaxWithdrawn(msg.sender, boomToken, unwithdrawnTotal, false);
    }
} 