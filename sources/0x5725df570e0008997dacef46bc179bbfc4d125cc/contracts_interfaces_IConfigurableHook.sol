// SPDX-License-Identifier: MIT
// Qian Exchange - https://qian.ag
pragma solidity ^0.8.24;

import "./IPoolManager.sol";

/**
 * @title IConfigurableHook
 * @notice Generic interface for hooks that can be configured by the factory
 * @dev All hooks that want to be auto-configured by QianDTMFactoryv4 must implement this interface
 * 
 * This allows the factory to remain hook-agnostic - new hooks can be added
 * without modifying the factory contract. Each hook:
 * 1. Defines its own config format (decoded from bytes)
 * 2. Validates its own constraints (tax limits, thresholds, etc.)
 * 3. Stores per-pool configuration
 * 
 * Example config encoding:
 * - AutoBuyBurnHook: abi.encode(uint16 buyTaxBps, uint16 sellTaxBps, uint256 threshold)
 * - TaxmanHook: abi.encode(uint16 buyTaxBps, uint16 sellTaxBps)
 * - FutureHook: abi.encode(param1, param2, param3, ...)
 */
interface IConfigurableHook {
    /**
     * @notice Configure the hook for a newly deployed token's pool
     * @param poolId The pool identifier (keccak256 of PoolKey)
     * @param tokenAddress The token address being configured
     * @param config Hook-specific configuration data (abi.encoded)
     * @dev Called by factory during deployCoin(). Must validate and store config.
     *      Should revert if already configured (immutability) or invalid params.
     */
    function configureHook(
        bytes32 poolId,
        address tokenAddress,
        bytes calldata config
    ) external;
    
    /**
     * @notice Get the pool ID from a PoolKey
     * @param key The pool key
     * @return poolId The computed pool identifier
     */
    function getPoolId(PoolKey calldata key) external pure returns (bytes32);
    
    /**
     * @notice Check if a pool has been configured for this hook
     * @param poolId The pool identifier
     * @return True if the pool is configured and enabled
     */
    function isConfigured(bytes32 poolId) external view returns (bool);
}

