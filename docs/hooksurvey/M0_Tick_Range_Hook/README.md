# M0 Tick Range Hook

> **地址**: [0xde400595199e6dae55a1bcb742b3eb249af00800](https://etherscan.io/address/0xde400595199e6dae55a1bcb742b3eb249af00800)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | M0 Tick Range Hook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeAddLiquidity`

## 属性

`vanillaSwap=True` `swapAccess=none`

## 功能描述

Restricts liquidity provision to a configurable tick range by reverting in beforeAddLiquidity if the position's ticks fall outside the allowed bounds. An authorized manager role can update the tick range.

## 调研结果

> 📚 **系列调研**：本 hook 与 [M0 Allowlist Hook](../M0_Allowlist_Hook/README.md) 共享同一个 `BaseTickRangeHook` 基类。完整对比、Tick 范围约束机制、Allowlist 体系、Predicate KYC 集成、管理员角色与时序图详见 [`family/m0-series.md`](../family/m0-series.md)。

### 收益结构

| 项 | 值 | 备注 |
|---|---|---|
| LP fee 抽成 | 无 | 不调用 `updateDynamicLPFee`，无 LP fee 覆盖 |
| Protocol fee | 无 | 0 protocol fee 抽成 |
| Tick 范围管理费 | 0 |  |
| `vanillaSwap` | True | hook 仅约束 LP tick 范围，不修改 swap 行为 |
| `swapAccess` | none | 不限制 swap，仅限制 LP |

### 工作原理（TickRangeHook 增量）

`TickRangeHook is BaseTickRangeHook`——是基类的最小化特化。唯一新增的就是构造函数和 `_beforeAddLiquidity` 的 override（仅调用 `super._beforeAddLiquidity(params_)`）：

```solidity
function _beforeAddLiquidity(
    address, /* sender */
    PoolKey calldata, /* key */
    IPoolManager.ModifyLiquidityParams calldata params_,
    bytes calldata
) internal view override returns (bytes4) {
    super._beforeAddLiquidity(params_);
    return this.beforeAddLiquidity.selector;
}
```

**核心约束**（继承自 `BaseTickRangeHook`）：
```solidity
if (params_.tickLower < tickLowerBound || params_.tickUpper > tickUpperBound)
    revert InvalidTickRange(params_.tickLower, params_.tickUpper, tickLowerBound, tickUpperBound);
```

任何 `modifyLiquidity` 操作（add / remove / 调整）只要新区间的 `[tickLower, tickUpper]` 与 hook 配置的 `[tickLowerBound, tickUpperBound]` 没有被包含关系（`params.tickLower >= tickLowerBound && params.tickUpper <= tickUpperBound`）就 revert。

**Manager 调整**：
```solidity
function setTickRange(int24 lo, int24 hi) external onlyRole(MANAGER_ROLE) {
    _setTickRange(lo, hi);  // require lo < hi
}
```

### 时序图

**LP Deposit / Modify**:
```
PositionManager
   │  modifyLiquidities([ModifyLiquidityParams{tickLower, tickUpper, ...}])
   ▼
PoolManager.unlock ──► hook.beforeAddLiquidity(sender=PM, key, params)
   │                       │
   │                       └─ tickLower < tickLowerBound || tickUpper > tickUpperBound?
   │                           ├─ 是 → revert InvalidTickRange
   │                           └─ 否 → 通过
   │
   └─ PoolManager 执行 LP 修改
```

**Manager 调整 TickRange**:
```
Manager (MANAGER_ROLE)
   │  setTickRange(newLo, newHi)
   ▼
   require newLo < newHi (TicksOutOfOrder revert)
   └─ 写 tickLowerBound / tickUpperBound
        emit TickRangeSet
```

### 风险与限制

1. **Manager 单点**：`MANAGER_ROLE` 是单一地址，可随时收紧或放宽 tick 范围。`manager_` EOA 私钥泄露 → 攻击者把范围设到 `[-887272, 887272]` 即可绕过约束。
2. **过窄 tick 范围会卡流动性**：初始 tick 必须落在 `[lo, hi]` 内；如果 manager 设置错误，池子无法启动。
3. **可被 LP 拆分规避**（理论）：LP 可以把"超出范围"的部分拆成多个小区间累积——只要每个小区间都在 `[lo, hi]` 内，约束不阻塞。这意味着约束是"最大边界"，不是"集中度强约束"。
4. **不可升级**（`upgradeable=False`）：bug fix 必须重新部署、迁移 LP。
5. **审计缺失**（`auditUrl: ""`）：本部署未见独立审计报告。
6. **30d 交易量 0 / 关联 Pool 数 N/A**：未观察到生产使用。
7. **不阻止 swap**：swapper 可以用任意区间交易；本 hook 只约束 LP 行为，对 swap 数学无影响。
8. **Remove Liquidity 不拦截**：`getHookPermissions` 中 `beforeRemoveLiquidity: false`——LPs 可以在已存在但已超出新范围的 LP 上 remove；如果 manager 把 `tickUpperBound` 收紧，已有 LP 仍可 remove。
