// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

/// Вспомогательный контракт для проверки существования пула
contract PoolView {
    using StateLibrary for IPoolManager;

    IPoolManager public immutable poolManager;
    constructor(IPoolManager _poolManager) { poolManager = _poolManager; }

    function poolExists(PoolKey memory key) external view returns (bool) {
        PoolId id = key.toId();
        try this._slot0(id) returns (int24) {
            return true;
        } catch {
            return false;
        }
    }

    function _slot0(PoolId id) external view returns (int24 tick) {
        (, tick,,) = poolManager.getSlot0(id);
    }
}
