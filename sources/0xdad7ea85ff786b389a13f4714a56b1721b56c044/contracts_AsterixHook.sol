// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AsterixHook is BaseHook, Ownable {
    using FixedPointMathLib for uint256;
    using SafeCast for int256;
    using SafeCast for uint256;
    using BalanceDeltaLibrary for BalanceDelta;

    uint24 internal constant MAX_HOOK_FEE = 1e6;

    address public immutable deadAddress;
    address public immutable treasury;
    address public mainTreasury;

    uint256 private _treasuryFeeBps;
    uint256 private _mainTreasuryFeeBps;

    error InvalidFeeBps();

    constructor(address _owner, address _deadAddress, IPoolManager _poolManager, address _treasury, address _mainTreasury) BaseHook(_poolManager) Ownable(_owner) {
        deadAddress = _deadAddress;
        treasury = _treasury;
        mainTreasury = _mainTreasury;
        _treasuryFeeBps = 80000;
        _mainTreasuryFeeBps = 10000;
    }

    function setFees(uint256 treasuryFeeBps_, uint256 mainTreasuryFeeBps_) external onlyOwner {
        if (treasuryFeeBps_ + mainTreasuryFeeBps_ >= MAX_HOOK_FEE) {
            revert InvalidFeeBps();
        }
        _treasuryFeeBps = treasuryFeeBps_;
        _mainTreasuryFeeBps = mainTreasuryFeeBps_;
    }

    function setMainTreasury(address _mainTreasury) external onlyOwner {
        mainTreasury = _mainTreasury;
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
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        (Currency unspecified, int128 unspecifiedAmount) = (params.amountSpecified < 0 == params.zeroForOne)
            ? (key.currency1, delta.amount1())
            : (key.currency0, delta.amount0());

        if (unspecifiedAmount == 0) return (this.afterSwap.selector, 0);
        if (unspecifiedAmount < 0) unspecifiedAmount = -unspecifiedAmount;

        uint256 treasuryFeeAmount = FullMath.mulDiv(uint256(int256(unspecifiedAmount)), _treasuryFeeBps, MAX_HOOK_FEE);
        uint256 mainTreasuryFeeAmount = FullMath.mulDiv(uint256(int256(unspecifiedAmount)), _mainTreasuryFeeBps, MAX_HOOK_FEE);

        if (unspecified.isAddressZero()) {
            poolManager.take(unspecified, treasury, treasuryFeeAmount);
        } else {
            poolManager.take(unspecified, deadAddress, treasuryFeeAmount);
        }
        poolManager.take(unspecified, mainTreasury, mainTreasuryFeeAmount);

        return (this.afterSwap.selector, treasuryFeeAmount.toInt128() + mainTreasuryFeeAmount.toInt128());
    }
}