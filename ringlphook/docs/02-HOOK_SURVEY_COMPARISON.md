# Hook 调研横向对比：为什么学谁，不学谁

基于 `docs/hooksurvey/` 50+ 个 hook 的深度调研，按**对 RingLPHook 的适用性**重新分层。

---

## 一、S 级：直接可抄的核心机制

### 1. StableStableHook（官方，$74M/30d）

| 维度 | 详情 |
|---|---|
| **核心公式** | `fee = base × exp(α × deviation)` |
| **deviation** | 当前价格 vs 可配置锚定价格（如 1.0） |
| **Flag** | `beforeInitialize` + `beforeSwap` |
| **复杂度** | 极简，~50 行核心逻辑 |

**为什么学**：
- 指数惩罚是**对套利者最狠的数学工具**——偏离 1% 时 fee 可能翻倍，偏离 5% 时 fee 指数级爆炸
- 公式简单 gas 低，适合高频 `beforeSwap` 调用

**为什么不照搬**：
- 必须知道"正确的锚定价格"——对任意 token pair（如 ETH/UNI）没有 1:1 锚定
- 解决方式：把 deviation 从"vs 固定锚定"改为"vs EMA"（见 [03-ALGORITHM_SELECTION.md](03-ALGORITHM_SELECTION.md)）

---

### 2. WETHHook（官方，$18M/30d）

| 维度 | 详情 |
|---|---|
| **功能** | ETH ↔ WETH 1:1 wrap via `beforeSwapReturnsDelta` |
| **Flag** | `beforeSwap` + `beforeSwapReturnsDelta` |
| **Fee** | 0（纯功能 hook） |

**为什么学**：
- 与 Ring Few 系列**完全同构**（fwWETH/fewUSDC 等也是 1:1 wrap）
- WETHHook 被 Universal Router 原生支持，gas 优化到位
- Ring Few Hook 可以对照补齐：集成方式、错误处理、ETH 路径

**为什么不照搬**：
- WETHHook 是**纯 wrap，无 fee 逻辑**，RingLPHook 需要在 wrap 之上叠加动态 fee

---

### 3. EMADynamicFeeHook（Ethereum，Immutable）

| 维度 | 详情 |
|---|---|
| **核心** | EMA 价格 + 30-step fee schedule (0.01% → 3.00%) |
| **Anti-JIT** | 300-block cooldown |
| **Flag** | `beforeInitialize` + `beforeSwap` |
| **Owner** | **无**（完全 immutable） |

**为什么学**：
- **任意 pair 可用**：EMA 是"自参考"的，不需要外部锚定价格
- **完全 immutable**：无 owner/admin，信任最小化，LP 敢存大钱
- Anti-JIT 是 v4 hook 中**最标准的 JIT 保护**（>300 blocks 视为长期 LP）

**为什么不照搬**：
- 30-step 是**线性/阶梯式**的，对"快速偏离"反应不够狠
- 缺乏 surge 熔断机制（闪电贷瞬间砸盘时 EMA 还来不及反应）
- 解决方式：把 StableStableHook 的指数公式嫁接到 EMA 偏离上

---

### 4. Custom Fee MEV Protection Hook（Ethereum）

| 维度 | 详情 |
|---|---|
| **核心** | 方向性 buy/sell fee override + blacklist + cooldown + max sell |
| **Flag** | `beforeInitialize` + `beforeSwap` |
| **Properties** | `dynamicFee = true` |

**为什么学**：
- **方向性 fee**：buy 和 sell 设不同费率，可根据历史资金流向动态调节
- **Repeat-swap penalty**：同一地址短时间内重复 swap fee 倍增
- **Max sell limit**：单笔卖出量上限，防砸盘
- 这些功能**可以直接叠加**到 Few Hook 的 `beforeSwap` 里，不需要改现有 wrap 逻辑

**为什么不照搬**：
- Blacklist 机制有**中心化风险**（owner 可以定向封锁地址）
- RingLPHook 选择**纯经济手段**（高 fee 劝退）而非**访问控制**（黑名单禁止）

---

## 二、A 级：借鉴思路，但不照搬

### 5. BunniHook（Ethereum，最复杂 v4 Hook）

| 维度 | 详情 |
|---|---|
| **机制** | surge fee + am-AMM + FloodPlain rebalance + TWAP oracle |
| **Fee 模型** | LP fee + hook fee + referral reward + am-AMM bid（四层叠加） |
| **复杂度** | 25K+ 字节代码，依赖 AmAmm/Flood/Solady/Permit2 |

**为什么学 surge fee**：
- 当价格**突变**（如 1 个 block 内跌 1%），自动把 fee 拉到顶（如 3%），然后按 halfLife（300-600s）指数衰减
- 这是 EMA 的完美补充：EMA 对"缓慢偏离"反应好，surge 对"瞬间砸盘"反应好

**为什么不做 am-AMM**：
- 需要 LP 把头寸 NFT（BunniToken）抵押来竞价，认知成本高
- 对低频交易对（fewToken 场景）**冷启动失败**——没人愿意为一个低交易量池子持续出价
- am-AMM 的"押金被 burn"机制会让 LP 觉得风险不可控

**为什么不做 FloodPlain rebalance**：
- RingLPHook 不是**集中流动性（CL）池**，不需要 tick 区间 rebalancing
- FloodPlain 是 Dutch auction 重平衡，对 Ring 是**过度设计**

**为什么不做 hook fee**：
- Bunni 抽 hook fee（~10-20% 的 swapFee）给协议方
- RingLPHook Phase 1 **0% protocol fee**，全部给 LP，最大化 APY 吸引流动性

> **结论：只抄 surge fee 思想，其余对 Ring 是过度设计。**

---

### 6. BVCC Dynamic Fee Hook（Base，$31M/30d）

| 维度 | 详情 |
|---|---|
| **核心** | gas price × volatility × 24h volume × repeat-penalty 四维复合费率 |
| **Flag** | `beforeInitialize` + `beforeSwap` + `afterSwapReturnsDelta` |
| **Owner** | 多角色访问控制 |

**为什么不照搬**：
- **过度设计**：对 1:1 锚定池（fewToken）或普通 pair 来说，四维复合是**用 complexity 换 marginal gain**
- **关键风险**（调研文档列了 18 条）：
  - `tx.origin` 可被绕过（Flashbots bundle）
  - circuit breaker 频繁误触发，正常交易者被误伤
  - 角色密钥泄露 = 攻击者可定向收割（改费率参数）
- 对 RingLPHook 的目标（简单、immutable、LP 敢存），这些风险不可接受

**可借鉴的点**：
- Repeat-swap penalty 的**衰减公式**（不是简单倍增，而是按时间指数衰减）
- 但实现方式要简化到单维度（block-based），不依赖 gas/volume/volatility 外部输入

---

### 7. Angstrom（Ethereum，$268M/30d）

| 维度 | 详情 |
|---|---|
| **定位** | 反 MEV DEX：应用级拍卖 + Solver 网络 + 内部撮合 |
| **Flag** | `requiresCustomSwapData = true`（强制自定义 calldata） |
| **审计** | Spearbit，Oct 2024 |

**为什么不做（核心原因）**：

| 层面 | 问题 |
|---|---|
| **运营成本** | 需要自建/运营 Solver 网络（类似 CowSwap 的 solver 竞争），这不是 hook 代码能解决的 |
| **基础设施** | EIP-712 签名验证、内部订单簿、批量撮合——全部需要链下组件 |
| **LP 收益非线性** | Angstrom 的 $268M 交易量是**整个 Solver 生态**支撑的结果，不是单靠 hook 实现的 |
| **外部集成成本** | `requiresCustomSwapData = true` 意味着普通 swap router（如 Uniswap Frontend、1inch、MetaMask）**无法直接调用**，必须走 Angstrom 专用入口 |

> **设计思路可以借鉴**：
> - "把 MEV 内部化"的理念（让套利价值回流给 LP）
> - 但实现方式 RingLPHook 选择**纯 on-chain 经济手段**（高 fee），而非**链下拍卖**

---

## 三、B 级及以下：不适合 Ring

| Hook | 为什么不适合 |
|---|---|
| **Sat1 Hook** | RFQ/P2P 撮合模式，与 Ring 的 AMM 池定位完全不同；源码不公开 |
| **VirtualLBP** | 拍卖守门员，不抽费，是做 token launch 用的，不是 LP 保护 |
| **UpegHook** | 存 SVG + 更新 random seed，纯娱乐性功能 |
| **M0 AllowlistHook** | 链上 KYC + ACL，违背"完全开放吸引外部 LP"的目标 |
| **TokenWorks 系列** | 时间衰减税模型（99%→10%），创作者经济/Launchpad 专用 |
| **Arrakis Private Hook** | 限制流动性添加给授权模块，私有金库模式 |
| **Ring 现有 9 个 Few Hook** | 仅做 1:1 wrap，zero fee，无保护功能——是新 hook 的"基础层"而非"竞争层" |

---

## 四、对比总表

| Hook | 动态 Fee | Anti-MEV | 任意 Pair | Immutable | 复杂度 | Ring 采用度 |
|---|---|---|---|---|---|---|
| StableStableHook | ✅ 指数 | ❌ | ❌（需锚定） | ❌ | 低 | **公式参考** |
| EMADynamicFeeHook | ✅ EMA阶梯 | ✅ Anti-JIT | ✅ | ✅ | 低 | **核心基底** |
| CustomFeeMEVHook | ✅ 方向性 | ✅ 多层 | ✅ | ❌ | 低 | **机制参考** |
| BunniHook | ✅ surge+动态 | ✅ am-AMM | ✅ | ❌ | **极高** | **只抄 surge** |
| BVCC | ✅ 四维复合 | ✅ 反机器人 | ✅ | ❌ | 高 | **不采用** |
| Angstrom | ✅ 拍卖定价 | ✅ 完全消除 | ✅ | N/A | **极高** | **不采用** |
| **RingLPHook（目标）** | **✅ EMA+指数+surge** | **✅ 经济手段** | **✅** | **✅ 核心immutable** | **中** | **——** |

---

## 五、选择逻辑总结

```
RingLPHook = 
    EMADynamicFeeHook 的"任意 pair + immutable + Anti-JIT"基底
  + StableStableHook 的"指数惩罚"公式强度
  + BunniHook 的"surge 熔断"思想（纯 on-chain 简化版）
  + CustomFeeMEVHook 的"方向性 fee + repeat penalty"机制
  - 所有复杂/链下/中心化的组件
```

---

*下一篇：[03-ALGORITHM_SELECTION.md](03-ALGORITHM_SELECTION.md) — StableStableHook vs EMADynamicFeeHook 的详细数学对比与选择过程*
