# BunniHook

> **地址**: [0x00001f3b9712708127b1fcad61cb892535951888](https://etherscan.io/address/0x00001f3b9712708127b1fcad61cb892535951888)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | BunniHook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`afterInitialize`, `beforeAddLiquidity`, `beforeSwap`, `beforeSwapReturnsDelta`

## 属性

`dynamicFee=True` `swapAccess=none`

## 功能描述

Core hook for Bunni v2, a concentrated liquidity protocol on Uniswap v4. Implements a virtual AMM with dynamic fees (TWAP-based + surge detection), am-AMM bidding for LVR/MEV recapture, auto-rebalancing via FloodPlain, and an on-chain price oracle.

## 调研结果

### 收益结构

Bunni v2 的 fee 模型是**多层叠加**——任何一个 swap 的最终费率由三层费用决定：

| 层 | 名称 | 大小 | 用途 |
|---|---|---|---|
| 1 | LP swap fee | 动态（surge fee 调控） | 给 LPs（标准 v4 LP fee） |
| 2 | Hook fee | `swapFee * hookFeeModifier / 1e6` | 给 `hookFeeRecipient`（协议方） |
| 3 | Referral reward | `hookFee * referralRewardModifier / 1e6` | 给 referrer（可选） |
| 4 | am-AMM bid | 由 am-AMM manager 在 swap 期间出价 | 用于 LVR/MEV recapture，归 am-AMM manager |

**Hook fee 计算（`BunniHookLogic.beforeSwap` 中）**：
```solidity
swapFeeAmount = amount * swapFee / 1e6;  // v4 swap fee 取整
hookFeesAmount = swapFeeAmount.mulDivDown(hookFeeModifier, MODIFIER_BASE);
// 当 am-AMM 启用时，hookFeesAmount 直接给 am-AMM manager (useAmAmmFee 分支)
// 否则扣减：swapFeeAmount -= hookFeesAmount
```

**Surge fee**（LVR 保护）：
- pool 的 `surgeFeeHalfLife` / `surgeFeeAutostartThreshold` 配置（`HookParams`）决定 surge 衰减
- vault share price 突变（`vaultSurgeThreshold0/1`）触发 surge 启动
- surge 启动后，swapFee 临时上调，按 `halfLife` 指数衰减

**am-AMM 机制**：
- LPs / 第三方通过 `IBunniHub.bunniTokenOfPool(id).transferFrom(...)` 把 BunniToken 抵押给 hook，换取出价权
- 每个 pool 的 am-AMM 由"出价最高者"赢得本笔 swap 的额外 fee（`useAmAmmFee` 分支）
- 失败/到期：`BunniToken` 被 burn（无 rent 退还）；`MIN_RENT` 防止 dust 攻击
- K 参数（构造函数 immutable）：am-AMM 的 bonding curve 常数

**Rebalancing 收益**：
- `rebalanceThreshold` 触发后，BunniHub 在 FloodPlain Dutch auction 下单
- 套利者（"rebalancer"）通过 `rebalanceOrderPreHook` / `rebalanceOrderPostHook` 完成 swap
- 套利者赚取价差（=LP 端的 LVR recapture），不直接给 hook fee
- `rebalanceMaxSlippage` / `rebalanceTwapSecondsAgo` 控制滑点

**典型费率（公开生产部署样本）**：
- LP fee 基础：~5 bps（500 / 1e6）
- Hook fee modifier：~10-20%（hookFeeModifier = 100_000~200_000 / 1e6）
- am-AMM max fee：~10 bps（10_000 / 1e6，per HookParams）
- Referral reward：~50%（referralRewardModifier = 500_000 / 1e6）

### 工作原理

**BunniHook 是 Uniswap v4 hook 体系中最复杂的实现之一**——它把 v4 池子改造成一个**虚拟 AMM**，并把 LVR/MEV 内部化。

**核心组件**：

1. **`BunniHub`（不在 hook 内）**：管理 pool 的 LP、tokenization、rebalance 状态机；`poolManager.setOperator(address(hub_), true)` 让 hub 在 hook 控制下修改流动性。
2. **`FloodPlain`（外部）**：Dutch auction 协议，用于 rebalance 时把"重平衡订单"拍卖给套利者。
3. **`AmAmm`（继承自 `biddog`）**：am-AMM 机制；本 hook 实现了 `_K` / `MIN_RENT` / `_amAmmEnabled` / `_payloadIsValid` / `_burnBidToken` / `_pullBidToken` / `_pushBidToken` / `_transferFeeToken` 等 hooklet 函数。
4. **`Oracle`**：在 `_afterInitialize` 中启动 TWAP 累积；`observe()` 公开读 API。
5. **`HookStorage`（`s`）**：所有 pool 状态（`slot0s`、`observations`、`ldfStates`、`rebalanceOrderHash` 等）。

**Hook flags**：
- `afterInitialize` 必需：BunniHub 必须在池子初始化后写入 slot0 / observation
- `beforeAddLiquidity` 必需：BunniHub 在 `modifyLiquidity` 之前协调 rebalance 状态
- `beforeSwap` 必需：动态 fee + am-AMM
- `beforeSwapReturnsDelta = true`：`useAmAmmFee` 路径下，hook 会返回 `BeforeSwapDelta` 把 fee 推入 hook 账上
- **没有** `afterSwap` / `afterAddLiquidity` 等

**Owner 权限**（`Ownable` 单点）：
- `setZone(IZone)`：换 rebalance 用的 Flood zone
- `setHookFeeRecipient(address)`：改 hook fee 收钱地址
- `setModifiers(hookFee, referral)`：动态改 fee 比例

**Hub-only 权限**：
- `updateLdfState(id, newState)`：BunniHub 才能更新 LDF state（Liquidity Density Function）
- `afterInitialize` / `beforeAddLiquidity` / `unlockCallback`：仅 PoolManager 可调（`poolManagerOnly`）

**EIP-1271 合规**：`isValidSignature(hash, signature)` 把 signature 字段当 `PoolId` 用，验证 rebalance 订单 hash 与之前授权的 hash 匹配。

**Unlock callback（3 种）**：
- `REBALANCE_PREHOOK`：从 hub 拉 rebalance 输入 → burn claim token → take 真实 token
- `REBALANCE_POSTHOOK`：把 rebalance 输出 settle 到 PM → mint claim token → 推回 hub
- `CLAIM_FEES`：burn 累积的 hook fee → 提给 `hookFeeRecipient`（ETH 自动 wrap WETH）

**Hook fee 提交流程**：
```solidity
function claimProtocolFees(Currency[] calldata currencyList) external nonReentrant {
    poolManager.unlock(abi.encode(HookUnlockCallbackType.CLAIM_FEES, abi.encode(currencyList)));
}
```
→ `_claimFees`：每个 currency 计算 `poolManager.balanceOf(this, currencyId) - _totalFees[currency]`（扣掉 am-AMM 累积），burn + take → recipient。

### 时序图

**Pool 初始化（only BunniHub）**：
```
BunniHub.deployPool(key, hookParams)
   │
   ├─► poolManager.initialize(key, sqrtPriceX96)
   │      └─► hook.afterInitialize(caller=hub, key, sqrtPriceX96, tick)
   │             └─► BunniHookLogic.afterInitialize(s, ...)
   │                   ├─ require caller == hub (防非 hub 初始化)
   │                   ├─ 初始化 slot0 (lastSwapTimestamp = block.timestamp)
   │                   ├─ 初始化 oracle 状态
   │                   └─ emit 事件
   │
   └─► hub.hookHandleDeposit(...)   // 后续 LP
```

**Swap (有 am-AMM 出价)**：
```
User (任何 sender)
   │  poolManager.swap(key, params)
   ▼
PoolManager.unlock ──► hook.beforeSwap(sender, key, params)
                          │
                          ├─► BunniHookLogic.beforeSwap(...)
                          │      │
                          │      ├─ 读 am-Amm 出价：BunniToken 持有者 (current manager)
                          │      ├─ 计算 swapFee（含 surge 衰减）
                          │      ├─ 计算 hookFeesAmount = swapFeeAmount * hookFeeModifier / 1e6
                          │      ├─ useAmAmmFee = true  → swapFeeAmount 全部给 am-Amm manager
                          │      ├─ 计算 referral reward (若有 ref)
                          │      ├─ mint 累积 claim token
                          │      └─ return (useAmAmmFee=true, manager, currency, amAmmFeeAmount, delta)
                          │
                          ├─► _accrueFees(manager, currency, amAmmFeeAmount)  // am-AMM 路径
                          │      └─► poolManager.mint(manager, currencyId, amount)
                          │
                          └─ return (BunniHook.beforeSwap.selector, beforeSwapDelta, 0)
   │
   ▼
PoolManager 执行集中度 swap（fee 已被动态调节）
```

**Rebalance（套利者执行）**：
```
套利者
   │  通过 FloodPlain 拍卖到 rebalance 订单
   ▼
FloodPlain
   │  hook.rebalanceOrderPreHook(args)  (only FloodPlain)
   ▼
   ├─ require orderHash == s.rebalanceOrderHash[id]  (防伪造)
   ├─ tstore output balance before
   ├─ poolManager.unlock(REBALANCE_PREHOOK, abi.encode(...))
   │     └─ _rebalancePrehookCallback:
   │           ├─ hub.hookHandleSwap(...)  (拉 input)
   │           ├─ hub.lockForRebalance(key)
   │           ├─ poolManager.burn(this, currencyId, amount)
   │           └─ poolManager.take(currency, this, amount)
   ├─ 检查 balance >= args.amount
   └─ WETH wrap（如 input 是 native ETH）

   │ 套利者执行 v3-style swap
   ▼
FloodPlain
   │  hook.rebalanceOrderPostHook(args)
   ▼
   ├─ require orderHash 仍匹配
   ├─ delete s.rebalanceOrderHash[id] / s.rebalanceOrderPermit2Hash[id] / s.rebalanceOrderDeadline[id]
   ├─ surge fee 重置：lastSwapTimestamp / lastSurgeTimestamp = block.timestamp
   ├─ 计算 orderOutputAmount = balanceOfSelf - tload(REBALANCE_OUTPUT_BALANCE_SLOT)
   ├─ 如 ETH：weth.withdraw(...)
   ├─ poolManager.unlock(REBALANCE_POSTHOOK, abi.encode(...))
   │     └─ _rebalancePosthookCallback:
   │           ├─ poolManager.sync(currency)
   │           ├─ currency.transfer(poolManager, amount)
   │           ├─ poolManager.settle{value: ...}()
   │           ├─ poolManager.mint(this, currencyId, paid)
   │           ├─ hub.unlockForRebalance(key)
   │           └─ hub.hookHandleSwap(inputAmount=paid, outputAmount=0)
   └─ BunniHookLogic.recomputeIdleBalance(s, hub, key)
```

**Hook fee 提取**：
```
任何 caller
   │  hook.claimProtocolFees([currency0, currency1, ...])
   ▼
   ├─ poolManager.unlock(CLAIM_FEES, abi.encode(currencyList))
   │     └─ _claimFees:
   │           ├─ for each currency:
   │           │     ├─ balance = balanceOf(this, currencyId) - _totalFees[currency]
   │           │     ├─ poolManager.burn(this, currencyId, balance)
   │           │     ├─ ETH: take + weth.deposit + weth.transfer(recipient)
   │           │     └─ ERC20: poolManager.take(currency, recipient, balance)
   │           └─ emit ClaimProtocolFees(currencyList, recipient)
```

### 风险与限制

1. **Owner 单点**：`setZone` / `setHookFeeRecipient` / `setModifiers` 全是 `onlyOwner`——Owner 私钥泄露 = 攻击者改 fee 比例（最高 100%）、收钱地址、rebalance zone。
2. **`setModifiers` 上限**：`hookFeeModifier ≤ MODIFIER_BASE`、`referralRewardModifier ≤ MODIFIER_BASE`（`MODIFIER_BASE = 1e6`）——验证在校验时进行，但 owner 仍可设到 100%，把整笔 fee 转给 hook。
3. **rebalance 订单伪造**：`isValidSignature` 把 `signature` 字段当 `PoolId` 解码，匹配 `rebalanceOrderPermit2Hash`——若 am-AMM 出价者或 hub 内部状态被攻陷，攻击者可签任意 rebalance 订单。
4. **tstore 临时存储**：`REBALANCE_OUTPUT_BALANCE_SLOT` 是 EIP-1153 transient storage，跨 tx 不保留——若 prehook 与 posthook 不在同一笔 tx 内（正常情况不会，但 EVM 异常或 hooklet bug 可导致），output 计算会失效。
5. **`hub.lockForRebalance` 重入保护**：依赖 hub 自身——若 hub 有 bug，可绕过 lock。
6. **`MIN_RENT` 计算含 `mulWadUp` + BunniToken.totalSupply**：min rent 与 BunniToken 供应量挂钩——若 token 大量 mint/burn，min rent 波动大，am-AMM 参与门槛不固定。
7. **`_K` immutable**：构造函数固定——如果 K 选错（太高=租金太贵没人参与 am-AMM；太低=易被 dust 攻击），整个 hook 不可调整。
8. **WETH unwrap 信任**：`weth.withdraw(orderOutputAmount)` 假设 WETH 合约不收费——Solady WETH 实现是 non-standard，但合约明确接受这一假设。
9. **Surge fee 自动衰减**：`surgeFeeAutostartThreshold` 时间后强制衰减——若市场持续偏离，pool 会在 threshold 后回落到低 fee，套利者集中涌入。
10. **Oracle 累积依赖 `afterInitialize`**：若 hub 因任何原因跳过 `afterInitialize`（如直接走 `poolManager.initialize`），oracle 状态缺失，所有 `observe()` 调用 revert。
11. **am-AMM 拍卖机制复杂度**：失败/到期 `BunniToken` 被 burn——若出价者对市场判断错误，永久损失 BunniToken 抵押。
12. **不可升级**（`upgradeable=False`）：整个 hub-orchestrated 架构如需调整 fee policy、am-AMM 参数，必须重新部署并迁移 LP。
13. **审计缺失**（`auditUrl: ""`）：合约代码量 25K+ 字节 + 多个外部依赖（AmAmm、Flood、Solady、permit2），单独审计报告缺失。
14. **30d 交易量 0 / 关联 Pool 数 N/A**：本部署地址可能不是生产主流实例；Bunni v2 主流量需查其它链/地址。
15. **FloodPlain 重平衡依赖外部套利者**：若长时间没有套利者出价（gas 高、利润薄），pool 会偏离目标区间，IL 累积。
16. **`MAX_AMAMM_FEE` 限制**（在 `HookParams` 校验中）——am-AMM manager 不会出超过此值的 fee，但若参数设错（如设成 0），am-AMM 永远无法赢标。
