// SPDX-License-Identifier: UNLICENSED
// © 2025 TETRIS DAO LLC. All rights reserved.
pragma solidity =0.8.28;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {SafeERC20Upgradeable, IERC20Upgradeable} from "@openzeppelin-new/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin-new/contracts-upgradeable/proxy/utils/Initializable.sol";
import {BaseHook} from "./BaseHook.sol";

contract CustomHook is Initializable, BaseHook {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant ONE_HUNDRED_PERCENT = 100_0000; // 100%

    address public admin;
    uint24 public hookFeePercentage; // uniswap fee percentage (3000 = 0.3%, 500 = 0.05%)

    uint256[50] private _gap;

    event BeforeSwapLogged(uint256 hookFeePercentage);
    event AdminSet(address indexed admin);
    event HookFeeSet(uint256 indexed hookFeePercentage);

    modifier onlyAdmin() {
        require(msg.sender == admin, 'Not allowed');
        _;
    }

    constructor(IPoolManager poolManager) BaseHook(poolManager) {
        _disableInitializers();
    }

    function init(address newAdmin, uint256 hookFee) external initializer {
        require(newAdmin != address(0), 'Zero admin');
        require(hookFee <= ONE_HUNDRED_PERCENT, 'Fee to high');
        admin = newAdmin;
        hookFeePercentage = uint24(hookFee);

        emit AdminSet(newAdmin);
        emit HookFeeSet(hookFee);
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != admin, 'Duplicate');
        admin = newAdmin;
        emit AdminSet(newAdmin);
    }

    function setHookFee(uint256 newFee) external onlyAdmin {
        require(newFee != hookFeePercentage, 'Duplicate');
        require(newFee <= ONE_HUNDRED_PERCENT, 'Fee to high');

        hookFeePercentage = uint24(newFee);
        emit HookFeeSet(newFee);
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        poolManager.updateDynamicLPFee(key, hookFeePercentage);
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @notice Hook permissions
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
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
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
