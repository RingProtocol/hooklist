# Clanker Static Fee Hook

> **地址**: [0x6c24d0bcc264ef6a740754a11ca579b9d225e8cc](https://etherscan.io/address/0x6c24d0bcc264ef6a740754a11ca579b9d225e8cc)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Clanker Static Fee Hook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeInitialize`, `beforeAddLiquidity`, `beforeSwap`, `afterSwap`, `beforeSwapReturnsDelta`, `afterSwapReturnsDelta`

## 属性

`dynamicFee=True` `requiresCustomSwapData=True` `swapAccess=none`

## 功能描述

A Uniswap v4 hook for the Clanker token launchpad that enforces per-pool static LP fees configured at initialization, collects protocol fees on the paired token, and supports optional MEV-protection modules and pool extensions.

## 调研结果

### 收益结构

| 项 | 值 | 备注 |
|---|---|---|
| 池 LP fee 基础 | **双费率**：`clankerFee` 与 `pairedFee`（按方向选） | 见 `ClankerHookStaticFeeV2._setFee` |
| 池 LP fee 上限 | 10% (`MAX_LP_FEE = 100_000` / 1e6) | 初始化时校验 |
| MEV LP fee 上限 | 80% (`MAX_MEV_LP_FEE = 800_000` / 1e6) | 启动后 2 分钟内可被 MEV 模块上调 |
| Protocol fee | 固定 20% 的 LP fee (`PROTOCOL_FEE_NUMERATOR = 200_000`) | 抽成币种是 **paired token**（永远不是 clanker） |
| Protocol fee 路径 | `poolManager.mint(hook, pairedCurrencyId, fee)` → 下次 swap `_hookFeeClaim` → `burn` + `take(factory)` | 由 factory 收取 |
| MEV 模块窗口 | 2 分钟 (`MAX_MEV_MODULE_DELAY`) | 过期后自动失效 |
| 计费币种 | 仅 paired token（ETH pool 禁用） | 见 `ETHPoolNotAllowed` 与 `WethCannotBeClanker` |
| LP locker 自动 claim | 在每次 swap 前 `_lpLockerFeeClaim` → `IClankerLpLocker.collectRewardsWithoutUnlock(token)` | factory 部署的池才有 locker |
| Pool Extension 抽成 | 通过 `IClankerHookV2PoolExtension.afterSwap(...)` 二级插件 | 受 allowlist 限制 |

**单笔交易费率拆解（以 paired → clanker 为例）**：
- 方向判断：`zeroForOne != clankerIsToken0` ⇒ `swappingForClanker = true`（paired → clanker）
- 实际 `LP fee = pairedFee`
- `protocolFee = pairedFee * 20%`
- 对 ExactInput：`scaledProtocolFee = protocolFee * 1e18 / (1e6 + protocolFee)`，从 input 端扣除
- 对 ExactOutput：`scaledProtocolFee = protocolFee * 1e18 / (1e6 - protocolFee)`，追加到 output 端

**关键非对称**：paired 端走"输入抽税"，clanker 端走"输出抽税"——这意味着 paired→clanker 路径的 fee 实际小于 pairedFee 的 20%（因为分母变大）；clanker→paired 路径则要补足差额。文档/UI 需把这两个数字对调用方明示。

### 工作原理

**`ClankerHookStaticFeeV2` 是 `ClankerHookV2` 的一个静态费率特化**。整个 Clanker v2 hook 体系是一个可继承的基类 + 多种费率策略（静态、动态、MEV 模块等）共同组成的家族。

**核心组件**：

1. **`_initializePool` (ClankerHookV2)**：
   - 拒绝 ETH pool (`ETHPoolNotAllowed`)；`initializePoolOpen` 额外禁止 WETH 作 clanker
   - 把 clanker 是否在 token0 写入 `clankerIsToken0[poolId]`
   - `poolKey.fee = LPFeeLibrary.DYNAMIC_FEE_FLAG`（hook 必须用动态费率槽）
   - 触发 `poolManager.initialize` 后调用 `_initializeFeeData`（由子类 `ClankerHookStaticFeeV2` 实现，存 clanker/paired fee）
   - 触发 `_initializePoolExtensionData`（受 `poolExtensionAllowlist` 限制）

2. **`_beforeSwap` 流程**（`ClankerHookV2._beforeSwap`）：
   ```
   _setFee(poolKey, params)             // StaticFee 子类注入 updateDynamicLPFee
   _hookFeeClaim(poolKey)               // 上次 swap 的 hook fee → factory
   _lpLockerFeeClaim(poolKey)           // LP locker 的 rewards 主动收集
   _runMevModule(poolKey, params, data) // 2 分钟窗口内可上调 fee
   按 (isExactInput, swappingForClanker) 走 4 选 2 分支：
   - ExactInput && swappingForClanker  → 减小 amountSpecified（input 端扣 fee）
   - !ExactInput && !swappingForClanker → 增加 amountSpecified（output 端加 fee）
   - 其他 2 种情况（isExactInput && !swappingForClanker / !isExactInput && swappingForClanker）→ 在 _afterSwap 扣
   ```

3. **`_setFee`（StaticFee 特化）**：
   ```solidity
   uint24 fee = swapParams.zeroForOne != clankerIsToken0[poolKey.toId()]
       ? pairedFee[poolKey.toId()]
       : clankerFee[poolKey.toId()];
   _setProtocolFee(fee);
   IPoolManager(poolManager).updateDynamicLPFee(poolKey, fee);
   ```
   每次 swap 重写动态 fee 槽——所以 `dynamicFee=True`。

4. **`mevModuleSetFee` / `mevModuleOperational`**：
   - 只能由 pool 绑定的 mev module 调用
   - 上调 fee 但不超过 `MAX_MEV_LP_FEE = 80%`
   - 启动 2 分钟后自动过期（`poolCreationTimestamp + 2 min`）

5. **`_afterSwap` 流程**：
   - 处理 isExactInput && !swappingForClanker / !isExactInput && swappingForClanker 两种"事后扣费"
   - `unspecifiedDelta` 返回给 PoolManager 把 fee 推到 hook 名下
   - 重新调整 `delta` 让 user 实际拿到的输出"看起来"等于 `swapParams.amountSpecified`
   - `_runPoolExtension(...)`（try/catch 二级插件；失败仅 emit `PoolExtensionFailed`，**不影响 swap**）

6. **MEV 模块启动延迟**：`_beforeAddLiquidity` 在 mev 模块激活期 revert——迫使 LP 等模块超时再 deposit。

7. **Extension allowlist**：`poolExtensionAllowlist.enabledExtensions(...)` 决定哪些 extension 可挂——未注册 extension 启动时 revert。

### 时序图

**Factory 部署流程**：
```
Factory
   │
   ├─► ClankerToken.deploy()
   ├─► ClankerHookStaticFeeV2.initializePool(clanker, paired, tick, tickSpacing, locker, mevModule, poolData)
   │      │
   │      ├─ _initializePool → poolManager.initialize(poolKey, initialPrice)
   │      ├─ _initializeFeeData  (clankerFee / pairedFee 写入)
   │      └─ _initializePoolExtensionData (allowlist 校验 + extension.initializePreLockerSetup)
   │
   ├─► LP 初始 deposit
   │      │
   │      └─ _beforeAddLiquidity 检查 mevModuleOperational → 若激活则 revert MevModuleEnabled
   │
   └─► Factory.initializeMevModule(poolKey, data)
          │
          ├─ IClankerMevModule.initialize(...)
          ├─ extension.initializePostLockerSetup(...) (若 extension 存在)
          └─ mevModuleEnabled[poolId] = true     // 2 分钟窗口开启
```

**Swap 流程 (paired → clanker, ExactInput)**：
```
User
   │  swap(PoolKey, SwapParams{zeroForOne=?, amountSpecified<0, hookData=abi.encode(PoolSwapData)})
   ▼
PoolManager.unlock ──► hook.beforeSwap
   │                       │
   │                       ├─ _setFee → updateDynamicLPFee(poolKey, pairedFee)
   │                       ├─ _hookFeeClaim     (上次累积 → factory)
   │                       ├─ _lpLockerFeeClaim (LP locker collectRewards)
   │                       ├─ _runMevModule     (可能进一步 updateDynamicLPFee)
   │                       │
   │                       ├─ swappingForClanker = true, isExactInput = true
   │                       ├─ scaledProtocolFee = protocolFee * 1e18 / (1e6 + protocolFee)
   │                       ├─ fee = amountSpecified * scaledProtocolFee / 1e18
   │                       ├─ poolManager.mint(hook, pairedCurrencyId, fee)   // 预付 protocol fee
   │                       └─ return delta = toBeforeSwapDelta(-fee, 0)        // 把 fee 从 input 端扣掉
   │
   ├─ PoolManager 按缩小后的 input 做集中度 swap
   │
   └─ hook.afterSwap(delta, swapData)
          │
          ├─ isExactInput && !swappingForClanker 为 false → 此分支不抽
          ├─ isExactInput && swappingForClanker 为 true  → 修正 delta = (delta.amount0(), swapParams.amountSpecified)
          │   // 让 user 实际得到的 output 等于"不扣 fee 时的输出"
          └─ _runPoolExtension(...)                       // 二级插件，可能发抽成；try/catch 隔离
```

**MEV 模块提费**：
```
MevModule
   │  hook.mevModuleSetFee(poolKey, fee)
   ▼
hook 仅校验：mevModule[poolId] == msg.sender && mevModuleOperational(poolId)
             && fee > currentLpFee && fee <= MAX_MEV_LP_FEE
   └─ updateDynamicLPFee(poolKey, fee) + _setProtocolFee(fee)
```

### 风险与限制

1. **复杂 delta 修正**：`ClankerHookV2._afterSwap` 在 beforeSwap 已扣费的两种情况下，把 `delta` 改写成 `(..., swapParams.amountSpecified)`——这意味着 user 看到的"输出"是**按未扣 fee 时计算的输出**，但实际收到的是 `output - fee`。router/前端必须正确显示扣费后净额。
2. **`requiresCustomSwapData=True`**：hook 期待 `abi.encode(PoolSwapData({mevModuleSwapData, poolExtensionSwapData}))`——空 `hookData` 仍可走（`if (swapData.length > 0)`），但默认 `PoolSwapData` 是 `bytes(0) + bytes(0)`。这会让普通 UniversalRouter 路径变成"未授权给 mev module / extension"状态——但 `_runMevModule` 仅 `if mevModuleEnabled` 才进入，所以空 data 实际可用；但当 pool 有 extension 且没填 data 时，extension 的功能（如自定义 reward）会被绕过。
3. **MEV 窗口 2 分钟**：必须 2 分钟内完成 setup，超时后 mev module 自动 disable，且 `_beforeAddLiquidity` 在期间内 revert——这是双刃剑：保护 anti-sniper 但也阻塞 LP 操作。
4. **Pool Extension 失败仅 emit**：`_runPoolExtension` 用 try/catch 包裹——扩展 bug 不会炸 swap，但用户拿不到扩展的附加收益，且事件 `PoolExtensionFailed` 可能被攻击者触发 DoS（用恶意 `poolExtensionSwapData` 反复让扩展 revert）。
5. **ETH pool 禁用**：`ETHPoolNotAllowed` + `WethCannotBeClanker` 强制走 ERC20/ERC20 pair；Clanker 业务模型不允许原生 ETH 在 clanker 一侧。
6. **Protocol fee 全收 factory**：`take(feeCurrency, factory, fee)` 一次性把累计的 protocol fee 提给 factory，factory 内部再分配不透明。
7. **不可升级**（json 中 `upgradeable=False`）：费率策略错误需重新部署、迁移 LP。
8. **审计缺失**（`auditUrl: ""`）：Clanker 是公开 launchpad 平台，但本 hook 单独审计报告缺失；fork 自多个上游库（@uniswap/*、solady）的攻击面未单独评估。
9. **`MAX_LP_FEE = 10%`、`MAX_MEV_LP_FEE = 80%`**：MEV 极端情况下 LP fee 高达 80%——若未与用户明示，可能被误用为抢跑保护。
10. **`_hookFeeClaim` 在 beforeSwap 内**——意味着每次 swap 都会清空 hook 累积；如果 LP 出现"连续两笔 swap 中间无 LP 操作"的场景，hook fee 实时结算；但若 hook claim 失败（`take` revert），整个 swap 也会 revert。
11. **30d volume 0 / 关联 Pool 数 N/A**：本部署地址 `0x6c24...8cc` 可能不是生产主流实例，或仅用于测试；Clanker 主流量需查其它部署。
