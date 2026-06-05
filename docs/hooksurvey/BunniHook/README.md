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

### 设计原理（核心机制实现细节）

下面把 BunniHook 的 4 个核心机制拆到**参数 / 状态 / 数学 / 代码路径**层面，解释每一步是怎么算出来的。

---

#### 1. 动态费率（Surge Fee）

**目的**：当 fewToken / 集中度池子的"实际价格"被外部市场砸偏离时，自动抬 fee 抑制套利者，保护 LP 免受 LVR。

**触发条件**（`BunniHookLogic.beforeSwap` 内）：

```solidity
// 伪代码（基于 README 中描述的参数命名）
if (block.timestamp >= s.slot0s[id].lastSurgeTimestamp + surgeFeeAutostartThreshold) {
    // 自动衰减窗口已过：fee 回到 base
    surgeFee = 0;
} else {
    uint256 elapsed = block.timestamp - s.slot0s[id].lastSurgeTimestamp;
    // 指数衰减：surgeFee *= exp(-elapsed / halfLife)
    surgeFee = s.slot0s[id].lastSurgeFee * expWadDown(-int256(elapsed) * WAD / int256(surgeFeeHalfLife));
}
swapFee = baseSwapFee + surgeFee;
```

**关键参数**（在 `HookParams` 部署时确定，immutable）：

| 参数 | 含义 | 典型值（生产样本） |
|---|---|---|
| `surgeFeeHalfLife` | surge fee 衰减半衰期（秒） | 300-600s |
| `surgeFeeAutostartThreshold` | 多久未 surge 就强制归零 | 1 小时 |
| `vaultSurgeThreshold0/1` | vault share price 突变幅度（bps）触发 surge | 10-30 bps |
| `maxSwapFee` | surge 后 fee 的硬顶 | ~30 bps |

**触发逻辑**（在 `afterSwap` 或独立 `_checkSurge` 中）：
- 每次 swap 后，比对 vault share price（`s.vaultState[id].totalAssets` / `totalSupply`）
- 如果相对上一笔 swap 的 share price 变化超过 `vaultSurgeThreshold` → `lastSurgeTimestamp = block.timestamp; lastSurgeFee = maxSwapFee`
- 否则 fee 一直按 `halfLife` 指数衰减

**两段式设计的好处**：
- **立即抑制**：surge 触发瞬间 fee 直接拉到 `maxSwapFee`
- **自然恢复**：如果价格确实回到 peg 附近，新 swap 不再触发 surge，fee 在几个 `halfLife` 内回归 base
- **强制归零**：`autostartThreshold` 防止"陈旧 surge"——如果一整天没交易，surge 标记作废，下一笔按 base fee 起步

**与 am-AMM 的交互**：
- surge fee 抬的是 **LP swap fee**（=v4 标准 fee）
- am-AMM 是在 LP fee 之**外**额外加的 hook fee，两者叠加不冲突

---

#### 2. am-AMM 竞价（Adverse-Selection Auction Market Maker）

**目的**：把"未来一段 swap 流"拍卖给出价最高的第三方——**胜者**接管该段 swap 的 fee，**失败者**的押金被 burn。LP 实际拿到"base fee + am-AMM bid"，整体收益超过普通 v4 池。

**数据结构**（继承自 `biddog` 框架的 `AmAmm`）：

```solidity
struct AmAmmState {
    address manager;          // 当前出价最高者
    uint256 rent;             // manager 抵押的 BunniToken 数量
    uint256 deadline;         // 出价有效期
    bool enabled;             // pool 是否启用 am-AMM
}
```

**Bonding curve 常数 `_K`**（构造函数 immutable）：
- am-AMM 报价规则：`bidAmount = K * rent`（线性）或 `bidAmount = K * sqrt(rent)`（次线性）
- 决定"押 1 份 BunniToken 能换多少 fee 流"
- 选错 = dust 攻击或租金太贵无人参与

**完整生命周期**：

```
Step 1: 出价（任何地址调用 hook 上的 amAmmBid）
   │
   ├─ 旧 manager 的 BunniToken 退还（如果还活着）
   ├─ 计算 minRent = MIN_RENT (依赖 totalSupply，防止 dust)
   ├─ 校验：msg.value (BunniToken) >= minRent
   ├─ _pullBidToken(msg.sender, rent)    // transferFrom BunniToken → hook
   ├─ 旧 manager 的 token 被 burn（如果出价被超越）
   └─ 写 s.amAmmState[id] = {manager, rent, deadline, enabled}

Step 2: 赢标（每次 swap 走 beforeSwap）
   │
   ├─ 读 s.amAmmState[id].manager
   ├─ if (manager != address(0) && block.timestamp < deadline) {
   │      useAmAmmFee = true;
   │      amAmmFeeAmount = swapFeeAmount (整笔 LP fee 给 manager)
   │      return (selector, delta, 0);
   │  }
   │
   └─ _accrueFees(manager, currency, amAmmFeeAmount)
         → poolManager.mint(manager, currencyId, amount)  // mint 到 manager 在 PM 账上

Step 3: 失败 / 到期
   │
   ├─ if (block.timestamp >= deadline) {
   │      _burnBidToken(manager, rent)    // 永久 burn，无 refund
   │      s.amAmmState[id].manager = address(0);
   │  }
```

**`MIN_RENT` 抗 dust**：
```solidity
MIN_RENT = mulWadUp(K, BunniToken.totalSupply()) / MIN_RENT_DIVISOR
```
- 与 BunniToken 总量挂钩：池子越大，min rent 越高（防小池子被 dust）
- `MIN_RENT_DIVISOR` 是固定的缩放因子

**`useAmAmmFee` 路径对 v4 账本的影响**：
- `beforeSwapReturnsDelta=true`：hook 返回 `BeforeSwapDelta`，把整笔 fee 推入 v4 账本
- 这笔钱最终 mint 给 am-AMM manager（不是 LP）
- **LP 当笔的实际收入 = 0**——但因为 am-AMM 是"为未来 N 笔 swap 出价"，LP 拿到的是 am-AMM manager 预先付的"期权费"（BunniToken 抵押）

**为什么 LP 接受这种安排**：
- BunniToken 本身是 LP 的"未来 LP 头寸 NFT 化"产物
- LP 把 BunniToken 押给 am-AMM = LP 自己当 manager（自博弈）或卖给第三方
- 整体 = LP 把"被动承受 LVR"变成"主动卖出未来 swap 流"，确定性收入 > 套利侵蚀

---

#### 3. FloodPlain 自动 Rebalance

**目的**：集中度 LP 的头寸会随价格漂移偏离目标区间，**FloodPlain 协议**通过 Dutch auction 把"重平衡订单"拍卖给套利者，让 LP 永远保持在目标区间。

**触发条件**：

```solidity
// 在 BunniHub 的 modifyLiquidity 路径中检查
if (currentTick < s.slot0s[id].rangeLowerTick ||
    currentTick > s.slot0s[id].rangeUpperTick) {
    _enqueueRebalance(id);
}
```

**Dutch auction 流程**（跨多个区块）：

```
区块 N:   hub._enqueueRebalance(id)
            │  生成 rebalanceOrder = {poolId, inputAmount, minOutput, deadline}
            │  hook.s.rebalanceOrderHash[id] = keccak(order)
            │  hook.s.rebalanceOrderDeadline[id] = block.timestamp + 1h
            │
区块 N+1: 套利者监听 FloodPlain，看到"出价从 100 降到 50"
            │  认为 50 仍有利可图，提交"接单"交易
            │  FloodPlain 校验价格 ≥ 自己评估的利润线
            ▼
区块 N+2:  FloodPlain 调用 hook.rebalanceOrderPreHook(args)
            │  ├─ require keccak(args) == s.rebalanceOrderHash[id]
            │  ├─ tstore output_balance_before = balanceOf(this, outputCurrency)
            │  ├─ poolManager.unlock(REBALANCE_PREHOOK, abi.encode(args))
            │  │     └─ _rebalancePrehookCallback:
            │  │           ├─ hub.hookHandleSwap(inputAmount, outputAmount=0)
            │  │           ├─ hub.lockForRebalance(key)
            │  │           ├─ poolManager.burn(this, inputCurrencyId, amount)
            │  │           └─ poolManager.take(inputCurrency, this, amount)
            │  └─ 检查 balance >= args.amount（防 hooklet bug）
            │
            ▼ 套利者把 input token 拿去做 v3-style swap 换 output
            │
            ▼
区块 N+3:  FloodPlain 调用 hook.rebalanceOrderPostHook(args)
            │  ├─ require keccak(args) 仍匹配（防篡改）
            │  ├─ delete s.rebalanceOrderHash[id] / permit2Hash / deadline
            │  ├─ surge fee 重置：lastSwapTimestamp = block.timestamp
            │  │  (因为 rebalance 是"健康套利"，不该触发 surge)
            │  ├─ orderOutputAmount = balanceOfSelf - tload(REBALANCE_OUTPUT_BALANCE_SLOT)
            │  ├─ ETH: weth.withdraw(orderOutputAmount)
            │  ├─ poolManager.unlock(REBALANCE_POSTHOOK, abi.encode(args))
            │  │     └─ _rebalancePosthookCallback:
            │  │           ├─ poolManager.sync(outputCurrency)
            │  │           ├─ currency.transfer(poolManager, outputAmount)
            │  │           ├─ poolManager.settle{value: ...}()
            │  │           ├─ poolManager.mint(this, outputCurrencyId, paid)
            │  │           ├─ hub.unlockForRebalance(key)
            │  │           └─ hub.hookHandleSwap(paid, 0)  // 记录到 LP 账上
            │  └─ BunniHookLogic.recomputeIdleBalance(s, hub, key)
            ▼
         套利者赚 = orderOutputAmount - v3 swap input cost（=LVR recapture 给 LP）
```

**关键参数**：

| 参数 | 含义 | 作用 |
|---|---|---|
| `rebalanceMaxSlippage` | 套利者实际拿到与订单的偏差上限 | 防 Flood 操纵 |
| `rebalanceTwapSecondsAgo` | TWAP 回看窗口 | 校验价格合理性 |
| `rebalanceThreshold` | 偏离多少 tick 触发 rebalance | 控制频率 |
| `rebalanceOrderDeadline` | 订单过期时间 | 防 stale 单 |

**EIP-1271 校验**：
- `isValidSignature(hash, signature)` 中 `signature` 字段被当 `PoolId` 解码
- 验证 `hash == keccak(rebalanceOrder)` 且 `hash == s.rebalanceOrderPermit2Hash[id]`
- 也就是说**只有 hook 自己预先授权的 hash 才能通过 EIP-1271**——外部人无法伪造 rebalance 订单

**tstore 临时存储**（EIP-1153）：
- `REBALANCE_OUTPUT_BALANCE_SLOT` 在 prehook 写入，posthook 读取后清空
- 跨 tx 不保留 = 天然隔离，**但也意味着一旦 prehook/posthook 跨 tx（异常路径），output 计算会失效**
- Solady 的 tstore 实现保证 slot 互不干扰

**为什么 LP 接受 rebalance 的 gas 成本**：
- 套利者赚的是"LP 原本会被 sandwich 吃掉的 LVR"
- LP 用 rebalance 把这部分价值**主动回收**（虽然让给了套利者一部分，但比自己被吃 100% 强）
- 当 swap 流量大时，rebalance 频率 = 套利机会频率，LP 实际上是在"用 rebalance 折扣换 swap fee 增量"

---

#### 4. 链上 TWAP Oracle

**目的**：在 v4 集中度池子上提供原生的 TWAP（time-weighted average price）查询服务——v4 标准 oracle 接口需要 hook 自实现。

**初始化**（`_afterInitialize` 中）：

```solidity
function _afterInitialize(...) internal {
    // 启动 oracle 累积
    s.observations[id].initialize(block.timestamp, sqrtPriceX96);
    s.slot0s[id].lastSwapTimestamp = block.timestamp;
    s.slot0s[id].observationIndex = 0;
    s.slot0s[id].observationCardinality = INITIAL_CARDINALITY;  // 通常 1024
}
```

**累积逻辑**（每次 `afterSwap`）：

```solidity
function _updateOracle(id, sqrtPriceX96) internal {
    ObservationState memory obs = s.observations[id];
    uint256 timeElapsed = block.timestamp - obs.lastUpdateTimestamp;
    if (timeElapsed > 0) {
        // 累积 priceCumulative += sqrtPriceX96 * timeElapsed
        s.observations[id].priceCumulative += sqrtPriceX96 * timeElapsed;
    }
    // 写入新的 observation 到环形缓冲区
    s.observations[id].lastUpdateTimestamp = block.timestamp;
    // ... 写入 observations[(index + 1) % cardinality]
}
```

**读取 TWAP**（`observe(uint256[] calldata secondsAgos)`）：

```solidity
function observe(uint256 secondsAgo) external view returns (uint256 twapSqrtPriceX96) {
    // 在环形缓冲区中二分查找 ≈ secondsAgo 之前的那条 observation
    (uint256 timestamp0, uint256 priceCum0) = _binarySearchObservation(id, secondsAgo);
    (uint256 timestamp1, uint256 priceCum1) = _binarySearchObservation(id, 0);
    
    // TWAP = (priceCum1 - priceCum0) / (timestamp1 - timestamp0)
    twapSqrtPriceX96 = (priceCum1 - priceCum0) / (timestamp1 - timestamp0);
}
```

**关键设计**：
- **环形缓冲区**（circular buffer）：`observationCardinality` 个槽位循环写，节省 SSTORE
- **价格累积器**（priceCumulative）：单变量连续累积，二分查找时直接相减
- **Gas 优化**：view 函数纯链上计算，无需外部喂价

**与 surge fee 的耦合**：
- surge 触发时，hook 可能**用 TWAP 而非瞬时价格**判断偏离（`vaultSurgeThreshold`）
- 防止"瞬时插针"误触发 surge

**依赖 `afterInitialize` 的风险**（README 风险 10）：
- 如果 hub 因任何原因跳过 `afterInitialize`（如 `poolManager.initialize` 直接调），oracle 状态缺失
- 后续所有 `observe()` 调用 revert → 整个 hook 不可用
- 这是 hub-orchestrated 架构的"单点入口"特性

---

#### 四机制的协同关系

```
                 ┌─────────────────────┐
                 │     Trader swap     │
                 └──────────┬──────────┘
                            │
                            ▼
                 ┌─────────────────────┐
                 │   TWAP Oracle 更新  │ ← 累积 sqrtPriceX96
                 └──────────┬──────────┘
                            │
                            ▼
                 ┌─────────────────────┐
                 │  Surge fee 计算     │ ← 用 TWAP + 当前价判断
                 └──────────┬──────────┘
                            │
                            ▼
                 ┌─────────────────────┐
                 │  am-AMM 赢标检查    │ ← 当前 manager 出价
                 └──────────┬──────────┘
                            │
                            ▼
                 ┌─────────────────────┐
                 │  v4 集中度 swap     │
                 └──────────┬──────────┘
                            │
                            ▼
                 ┌─────────────────────┐
                 │  Tick 偏离检查      │ → 触发 FloodPlain rebalance
                 └─────────────────────┘
```

四个机制是**同一笔 swap 的不同阶段**：
- **TWAP** = 历史视角
- **Surge** = 风险视角
- **am-AMM** = 收益视角
- **FloodPlain** = 长期视角

LP 由此从"被动承受 LVR"变成"主动管理 LVR"——这是 Bunni v2 被称为"v4 hook 体系天花板"的原因。

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
