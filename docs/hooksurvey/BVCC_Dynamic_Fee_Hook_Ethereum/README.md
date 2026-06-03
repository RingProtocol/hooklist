# BVCC Dynamic Fee Hook (Ethereum)

> **地址**: [0xf9ced7d0f5292af02385410eda5b7570b10b50c4](https://etherscan.io/address/0xf9ced7d0f5292af02385410eda5b7570b10b50c4)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | BVCC Dynamic Fee Hook (Ethereum) |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`afterInitialize`, `beforeSwap`, `afterSwap`, `afterSwapReturnsDelta`

## 属性

`dynamicFee=True` `swapAccess=none`

## 功能描述

An advanced anti-bot Uniswap v4 hook by BlockVenture Chain Capital that dynamically adjusts LP fees based on gas price levels, volatility, and 24-hour pool volume. It applies a repeat-swap penalty to deter bot activity and collects a small hook fee from each swap's output amount.

## 调研结果

### 收益结构

| 项 | 值 | 备注 |
|---|---|---|
| 默认 base fee | 0.025% (`defaultBaseFee = 250` / 1e6) | 可由 FEE_MANAGER_ROLE 调整 |
| 池 base fee 上限 | 5% (`MAX_BASE_FEE = 50_000` / 1e6) | `poolBaseFees[poolId]` 单独配置 |
| 池 fee 绝对上限 | 7.5% (`ABSOLUTE_MAX_FEE = 75_000` / 1e6) | 包括动态 + penalty 后不能超过 |
| Repeat penalty 增量 | 2.5% (`REPEAT_PENALTY_FEE = 25_000` / 1e6) | 同一 `tx.origin` 5 分钟内重复 swap |
| Cooldown | 300 秒 (`COOLDOWN_SECONDS`) | `lastSwapTimestamp[poolId][user]` |
| Hook fee | 0.01% (`HOOK_FEE_UNITS=1` / `HOOK_FEE_DENOMINATOR=10_000`) | 抽 **output** 端 |
| Hook fee 路径 | `poolManager.take(feeCurrency, this, feeAmount)` → 累积 → `withdrawHookFees` / `withdrawNative` | 由 HOOK_FEE_MANAGER_ROLE 提取 |
| Emergency fee cap | 1% 默认 (`defaultEmergencyFeeCap = 10_000` / 1e6) | per-pool 覆盖；gas 极端时按 multiplier 拉满后被 cap |
| Gas tier multipliers | High: 5.6x / Very High: 6.5x / Extreme: 7.5x（按 base fee） | 仅 gas 超过 `veryHighGasThreshold` 走 emergency fee 路径 |
| Volatility multipliers | 1x / low / high / extreme（per `vol*Multiplier`） | `volLowThreshold` ~ `volExtremeThreshold` 切档 |
| Volume multipliers | veryLow / low / normal / high / veryHigh | 24h 累计交易量分档 |

**Fee 计算流水线**（`_calculateFeeByGasLevel`）：

```
1. 取 baseFee (poolBaseFees[poolId] / defaultBaseFee)
2. 检查 emergencyPaused (config.pausedEmergencyFees)：
   - 是 → finalFee = baseFee
3. 取当前 gasPrice (lastGasPriceCheck 缓存)
4. 分档：
   - normalGasThreshold 之内 → _calculateDynamicFee (vol × volume 复合)
   - highGasThreshold 之内 → baseFee * vol*Volume 复合
   - veryHighGasThreshold 之内 → emergencyFee = baseFee * veryHighGasMultiplier / 10000
   - 超过 veryHighGasThreshold → extremeFee = baseFee * extremeGasMultiplier / 10000
5. _applyEmergencyFeeCap(poolId, fee)：若超 defaultEmergencyFeeCap 或 pool 单独 cap，capped
6. _applyCircuitBreaker(poolId, fee)：若超 ABSOLUTE_MAX_FEE，capped
7. 回到 _beforeSwap：
   - 同一 user 5 分钟内重 swap：fee += REPEAT_PENALTY_FEE（再 cap）
   - LPFeeLibrary.validate(finalFee)
8. emit FeeCalculated
9. 返回 (selector, ZERO_DELTA, finalFee)  // updateDynamicLPFee 由 hook 第三返回值
```

**Hook fee 提取**（`_afterSwap`）：与上述 LP fee 独立
- 计算 `feeAmount = outputAmount / 10_000`（即 1 bp 的 hook 抽成）
- `poolManager.take(feeCurrency, this, feeAmount)` 把 fee 转入 hook
- 返回 `int128(feeAmount)` 让 PoolManager 从 user 的 output 端扣掉
- 累积在 hook 地址，由 `HOOK_FEE_MANAGER_ROLE` 调用 `withdrawHookFees` / `withdrawNative` 提取

### 工作原理

**定位**：anti-bot 套利保护 + 动态费率 + 协议抽成，**多档 gas-aware fee policy**——gas 高时费率暴涨，gas 低时回归 vol/volume 动态。

**核心组件**：

1. **`NetworkConfig`**：按 chainId 配置 gas threshold 和 emergency multiplier。构造函数硬编码 BSC / Arbitrum / Base / Optimism / Polygon，其它链通过 `setNetworkConfig` 配置。
2. **`PoolDynamicConfig`**：每个 pool 的 vol 阈值与 multiplier、volume 阈值与 multiplier、4 个 pause flag（dynamic / antibot / hookFee / emergency）。
3. **`PriceSnapshot[]`**：每个 pool 维护最多 4 个价格快照（间隔 `SNAPSHOT_INTERVAL = 900s`），用于波动率计算。
4. **`VolumeData`**：24h 滚动交易量，每小时聚合（`HOUR_SECONDS = 3600`），`hoursRecorded` 防溢出。
5. **`lastSwapTimestamp[poolId][user]`**：以 `tx.origin` 为 key 的"用户最后一次 swap 时间"映射。

**Hook flags**（注意与 `swapAccess=none` 对比）：
- `afterInitialize`：初始化 pool 时配置 `PoolDynamicConfig`（默认 threshold / multiplier 来自 `_initializePoolDynamicConfig`）
- `beforeSwap`：计算最终 fee + repeat penalty → 通过 `updateDynamicLPFee`（由 `_beforeSwap` 第三返回值触发）
- `afterSwap`：抽 hook fee（output 端 0.01%）

**Volatility 计算**（`_calculateVolatility`）：
```solidity
priceDiff = |currentPrice - historicPrice|
volatility = (priceDiff * 10000) / historicPrice
```

**`_calculateDynamicFee`**：
```solidity
totalMultiplier = volMultiplier * volumeMultiplier / 10000
finalFee = baseFee * totalMultiplier / 10000
if (finalFee > MAX_BASE_FEE) finalFee = MAX_BASE_FEE
```

**Gas tracking 优化**：`lastGasPriceCheck` / `currentGasPrice` 是合约级缓存，**仅在 `_calculateFeeByGasLevel` 中按需刷新**——但具体更新逻辑见 `_updateGasPrice`（README 撰写时未读取此函数），可能与 block 间隔或 cooldown 联动。

**多角色权限**（`AccessControl`）：
| 角色 | 默认 | 能力 |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | admin (构造函数) | grant/revoke 其它角色 |
| `FEE_MANAGER_ROLE` | admin | 设置 defaultBaseFee / defaultEmergencyFeeCap / poolBaseFees / poolEmergencyFeeCap / PoolDynamicConfig / pause 各档 |
| `HOOK_FEE_MANAGER_ROLE` | admin | `withdrawHookFees` / `withdrawNative` |
| `PAUSE_MANAGER_ROLE` | admin | 暂停/恢复 4 类 fee |

**Anti-bot 防御**：
- `tx.origin` 检测（不是 `msg.sender`）：意味着任何合约/路由器调用也算"用户是同一个人"
- 5 分钟 cooldown：高频套利者会被 penalty
- Gas-aware emergency fee：套利者大量抢跑时 gas 飙升 → 费率同步拉高

### 时序图

**Pool 初始化**：
```
BunniHub-like deployer (任何 caller)
   │
   ├─► poolManager.initialize(key, sqrtPriceX96)
   │      └─► hook.afterInitialize(...)
   │             ├─ 校验配置 (volLowThreshold < volHighThreshold < volExtremeThreshold)
   │             ├─ 校验 (volumeVeryLow < volumeLow < volumeHigh < volumeVeryHigh)
   │             └─ 初始化 dynamicConfigs[poolId] = { enabled: true, pausedX: false, ... }
   │
   └─► poolBaseFees[poolId] = defaultBaseFee  // 需 manager 显式调用 setPoolBaseFee
        poolEmergencyFeeCap[poolId] = defaultEmergencyFeeCap
```

**Swap 流程 (gas normal, no penalty)**：
```
User
   │  poolManager.swap(key, params)
   ▼
PoolManager.unlock ──► hook.beforeSwap(sender, key, params)
                          │
                          ├─ baseFee = poolBaseFees[poolId] || defaultBaseFee
                          ├─ (gasPrice, gasLevel, strategy) = _calculateFeeByGasLevel(...)
                          │     ├─ gas in [normal, high] → _calculateDynamicFee (vol*volume)
                          │     ├─ finalFee clamped to MAX_BASE_FEE
                          │     └─ _applyCircuitBreaker → finalFee clamped to ABSOLUTE_MAX_FEE
                          ├─ penalty check：tx.origin 在 cooldown 内？
                          │     ├─ 是 → finalFee += REPEAT_PENALTY_FEE
                          │     │        + _applyCircuitBreaker
                          │     └─ 否 → 不变
                          ├─ LPFeeLibrary.validate(finalFee)
                          ├─ lastSwapTimestamp[poolId][user] = block.timestamp
                          └─ return (selector, ZERO_DELTA, finalFee)
                              ▲
                              │   PoolManager 据此调用 updateDynamicLPFee(poolKey, finalFee)
                              │   → 后续 swap 按 finalFee 走 LP fee
   │
   ▼
PoolManager 执行 swap
   │
   ▼
hook.afterSwap(delta, ...)
   │
   ├─ pausedHookFee ? → return 0
   ├─ outputAmount = delta.amount0() or amount1() (按 zeroForOne)
   ├─ feeAmount = outputAmount / 10_000   (≈ 1 bp)
   ├─ feeCurrency = output token
   ├─ volume tracking (gas <= veryHigh 时按 24h 累积 / Lite 模式 6h 间隔)
   └─ poolManager.take(feeCurrency, this, feeAmount)
        return (selector, int128(feeAmount))   // PoolManager 从 user output 扣掉
```

**Swap 流程 (gas 极端，emergency fee)**：
```
hook.beforeSwap
   │
   ├─ gasPrice > veryHighGasThreshold
   ├─ extremeFee = baseFee * extremeGasMultiplier / 10000
   ├─ _applyEmergencyFeeCap(poolId, extremeFee)   // 默认 cap 1%
   │     └─ if extremeFee > cap: capped = cap; emit EmergencyFeeCapped
   ├─ _applyCircuitBreaker(poolId, capped)
   └─ return (selector, ZERO_DELTA, capped)  + penalty 流程同 normal
```

**Hook fee 提取**：
```
HOOK_FEE_MANAGER_ROLE
   │  withdrawHookFees(token=USDC, to=treasury, amount=100e6)
   ▼
   ├─ require token != address(0)
   ├─ balance = IERC20(token).balanceOf(this)
   ├─ require balance >= amount
   └─ IERC20(token).safeTransfer(to, amount)
        emit HookFeesWithdrawn

   // native
   │  withdrawNative(to=treasury, amount=1e18)
   ▼
   ├─ require address(this).balance >= amount
   └─ to.call{value: amount}("")
        emit NativeFeesWithdrawn
```

### 风险与限制

1. **`tx.origin` 作 anti-bot key**：`tx.origin` 易被绕过（合约内部调用方都共享同一个 origin）——实际可能误伤，也容易被构造合约"洗"出独立的 origin 路径绕过 cooldown。
2. **Hook fee 抽 output 端**：`afterSwap` 的 `int128(feeAmount)` 让 PoolManager 从 user 的 output 扣掉 1bp——但 LP fee 已由 `updateDynamicLPFee` 写入；user 实际承担 = `LP fee + hook fee`。
3. **`updateDynamicLPFee` 频率 = swap 频率**：每个 swap 都会覆盖 pool 动态 fee 槽，频繁 swap 时大量 SSTORE 写。
4. **dynamicFee=True 写动态 slot**：v4 的 `poolManager.updateDynamicLPFee` 是写操作——同一区块内的多笔 swap 顺序竞争可能导致 fee 槽"非原子"地被覆盖。
5. **Volume 阈值不准确**：`hoursRecorded < 24` 阶段，24h 累积量偏小（实际为 `hoursRecorded * avgHour`），volume 档位判定可能不准。
6. **PriceSnapshot 只保留 4 个**：长期 pool（运行 1 年以上）只能看到最近 4 个 15 分钟间隔的价格；volatility 计算窗口最多 60 分钟。
7. **Circuit breaker 多次触发**：`REPEAT_PENALTY_FEE` + emergency fee + circuit breaker 三层叠加——若 pool 配高 baseFee 且 gas 极端，fee 几乎肯定打 ABSOLUTE_MAX_FEE (7.5%)。
8. **`feeAmount <= ((uint256(1) << 127) - 1)` require**：边界保护；outputAmount 异常巨大时 revert（不通过 `_applyEmergencyFeeCap` 减损）。
9. **`_calculateFeeByGasLevel` 不带 gasPrice 缓存**（`currentGasPrice` / `lastGasPriceCheck` 在 README 撰写时未读取更新逻辑）：若缓存更新不及时，gas 飙升时 fee 调整延迟一两个 block。
10. **manager 角色可单方面 set poolBaseFees / setPoolEmergencyFeeCap**：FEE_MANAGER 可针对单池把 base fee 调高至 50_000、emergency cap 调高——若角色密钥泄露，hook 可被用作"定向 fee 收割"。
11. **anti-bot 暂停可控**：`pausedAntiBot = true` 时 repeat penalty 失效——FE_MANAGER 可选择性关闭 anti-bot。
12. **不可升级**（`upgradeable=False`）：bug 修复需要重新部署。
13. **审计缺失**（`auditUrl: ""`）：本合约代码量 40K 字节 + 复杂 fee 数学 + 多角色 + 多 pause 标志，未见独立审计报告。
14. **30d 交易量 0 / 关联 Pool 数 N/A**：本部署 `0xf9ce...0c4` 在 Ethereum 上未观察到生产使用；同 hook 在 Arbitrum (0x2097...0c4) 有部署但同样 N/A。
15. **Hook fee 提取**：`withdrawHookFees` 仅 `HOOK_FEE_MANAGER_ROLE` 可调——若该角色密钥丢失，累积 fee 永久 stuck。
16. **Hook fee 仅 ERC20 + native**：不直接支持其他 fee token（如 ERC-1155、LP token）——需先 swap。
17. **PoolDynamicConfig 初始 default**：构造函数**不自动**初始化每个 pool 的 `PoolDynamicConfig`——`afterInitialize` 才会；如果 manager 不调用 `_initializePoolDynamicConfig`，`paused*` flag 全为 false（默认），但 `vol*Threshold` 全为 0（`_calculateVolatilityMultiplier` 默认走 normal 档）。
18. **`_updateVolumeTracking` 在 high gas 时不更新**（`tx.gasprice > veryHighGasThreshold` 跳过）——emergency fee 路径不累积 volume，下一次 normal gas 时可能一次性跨档。
