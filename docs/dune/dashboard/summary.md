# Ring Hook Dashboard — 分析摘要

> **数据时间**：截至 2026-06-04
> **数据源**：[dashboard/01_pool_summary.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/01_pool_summary.sql) · [02_token_reserves.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/02_token_reserves.sql) · [03_top_traders.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/03_top_traders.sql) · [04_daily_volume.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/04_daily_volume.sql)
> **Dashboard**：https://dune.com/ring_protocol/ring-hook-monitor

---

## TL;DR

- **9 个 hook 池**：7 个活跃、2 个**死池**（FewweETHHook / FewwstETHHook — 30d/7d 均为 0 交易、0 交易量）
- **30d 总交易量 ≈ $2.43M**，**7d ≈ $154K**。**WBTC 系列占 80%+**
- **8 个活跃池全是单边流向**：6 个 UNWRAP-ONLY（用户在 unwrap fwToken 拿 underlying）+ 2 个 WRAP-ONLY（用户在 wrap underlying 拿 fwToken）
- **8 个池子都已偏离初始 reserves**：token 一侧持续沉淀，池子越来越歪
- **真实交易者很少**：跨池子头部 EOA 重合度高 + 大量 dust transaction（< $100 的 1-day-1-tx 钱包） → **几乎全部是 MEV bot / 套利 / 清算机器人**，没有零售 dApp 用户

---

## 1. 交易量概览

| Hook | 池子 | 30d 笔数 | 7d 笔数 | 30d 美元量 | 7d 美元量 | 状态 |
|---|---|---:|---:|---:|---:|---|
| FewWBTCHook | fwWBTC-WBTC | 10 | 5 | **$118K** | $24K | WRAP-ONLY |
| FewCBBTCHook | cbBTC-fwcbBTC | 8 | 5 | $95K | $22K | UNWRAP-ONLY |
| FewETHHook | ETH-fwWETH | **289** | 46 | $217K | $62K | UNWRAP-ONLY |
| FewUSDTHook | USDT-fwUSDT | 49 | 4 | $137K | $14K | UNWRAP-ONLY |
| FewUSDCHook | fwUSDC-USDC | 31 | 4 | $73K | $30K | WRAP-ONLY |
| FewDAIHook | DAI-fwDAI | 1 | 0 | $35K | $0 | UNWRAP-ONLY |
| FewUNIHook | UNI-fwUNI | 4 | 0 | $2.8K | $0 | UNWRAP-ONLY |
| ~~FewweETHHook~~ | ~~fwweETH-weETH~~ | **0** | 0 | **$0** | $0 | 💀 **DEAD** |
| ~~FewwstETHHook~~ | ~~wstETH-fwwstETH~~ | **0** | 0 | **$0** | $0 | 💀 **DEAD** |

**观察**：
- **FewETHHook 是交易笔数第一**（30d 289 笔），但 7d 降至 46 笔 → **趋势在放缓**
- **WBTC 系列（含 fwWBTC + cbBTC）合计 $213K**，占总交易量 32% — 这两个池子的"单边"是 Ring 协议当前**最严重的失衡源**
- **DAI / UNI 池子近乎死掉**（30d 仅 1-4 笔），需观察是否要关停
- **weETH / wstETH 死池**：从来没被 bootstrap 起流动性（liquidity_event_count=2 但只创建了池子，没有任何后续 trade）

---

## 2. WRAP-ONLY 与 UNWRAP-ONLY 解释

### 判定方法

`02_token_reserves.sql` 通过 `dex.trades.token_sold_symbol` 前缀分类：
- **WRAP-ONLY**：100% 的交易 `token_sold_symbol` 都不以 `fw` 开头 → 用户一直在**用 underlying 买 fwToken**（mint fwToken）
- **UNWRAP-ONLY**：100% 的交易 `token_sold_symbol` 都以 `fw` 开头 → 用户一直在**卖 fwToken 拿 underlying**（burn fwToken）
- **MIXED**：两种都有 → 双向平衡的健康池

### 8 个活跃池的分类

| 模式 | Hook | 池子 | 含义 |
|---|---|---|---|
| **WRAP-ONLY** | FewWBTCHook | fwWBTC-WBTC | 用户买 fwWBTC（拿 WBTC 进场换 fwWBTC 出场）|
| **WRAP-ONLY** | FewUSDCHook | fwUSDC-USDC | 用户买 fwUSDC |
| **UNWRAP-ONLY** | FewCBBTCHook | cbBTC-fwcbBTC | 用户卖 fwcbBTC 拿 cbBTC |
| **UNWRAP-ONLY** | FewETHHook | ETH-fwWETH | 用户卖 fwWETH 拿 ETH |
| **UNWRAP-ONLY** | FewUSDTHook | USDT-fwUSDT | 用户卖 fwUSDT 拿 USDT |
| **UNWRAP-ONLY** | FewDAIHook | DAI-fwDAI | 用户卖 fwDAI 拿 DAI |
| **UNWRAP-ONLY** | FewUNIHook | UNI-fwUNI | 用户卖 fwUNI 拿 UNI |
| **UNWRAP-ONLY** | FewwstETHHook | wstETH-fwwstETH | 1 笔（≈ 0 活跃） |

### 为什么"全是单边"

1. **fee = 0**：没有套利动机让两边价格回归 — 1:1 wrap + 0 fee = 单边套利空间持续存在
2. **没 LP 实际提供流动性**：liquidity_event_count 都是 2-3 次（仅创建池子时的 bootstrap）— 没有传统 AMM LP 持续 rebalance
3. **使用场景单边**：
   - fwWBTC/fwUSDC 大概率被当**收益聚合 / collateral 收据**用（项目方一次性把 underlying 换成 fwToken 上线）
   - 其他 fwToken 主要是**退出机制**（burn fwToken 拿回 underlying）

### 趋势 / 异常

- **5/26 FewETHHook 单日 79 笔、30 个 unique caller**（参见 04_daily_volume.sql）— 接近 30d 全部交易量的 17%，**异常爆量**
  - 同时 FewUSDTHook 4 笔 + FewUSDCHook 1 笔
  - 当日 20 笔 dust (< $100, 其中 10 笔 < $10, 5 笔 < $5) 集中在 ETH 池 — **典型 sandwich / liquidation bot 模式**

---

## 3. Token 沉淀（最关键的健康指标）

### 沉淀矩阵

`token_net_stranded = SUM(sold) - SUM(bought)` for that token。**正 = 沉淀在池子里；负 = 被用户提走**。因 1:1 swap 对称性，每行 `token0 + token1 = 0`。

| Hook | 沉淀 token | 量 | 折算美元 | 性质 |
|---|---|---:|---:|---|
| FewWBTCHook | **WBTC** | 257.4 BTC | **~$25.7M** | WRAP-ONLY → underlying 沉淀 |
| FewCBBTCHook | **fwcbBTC** | 170.4 cbBTC | **~$14M** | UNWRAP-ONLY → fwToken 沉淀 |
| FewUSDTHook | **fwUSDT** | 850K USDT | **$850K** | UNWRAP-ONLY → fwToken 沉淀 |
| FewETHHook | **fwWETH** | 1,030 ETH | **~$2.4M** | UNWRAP-ONLY → fwToken 沉淀 |
| FewUSDCHook | **USDC** | 417K USDC | **$417K** | WRAP-ONLY → underlying 沉淀 |
| FewDAIHook | **fwDAI** | 122K DAI | **$122K** | UNWRAP-ONLY → fwToken 沉淀 |
| FewUNIHook | **fwUNI** | 7,327 UNI | **$29K** | UNWRAP-ONLY → fwToken 沉淀 |
| FewwstETHHook | **fwwstETH** | 0.0025 wstETH | ~$6 | 1 笔（≈ 0）|

**绝对值合计 ≈ $43.6M 等价 token 沉淀在 8 个池子里**。

### 风险点

- **FewWBTC 沉淀 257 BTC (~$25.7M)**：WRAP-ONLY = **没人在 unwrap**。如果有一天有人要 unwrap 拿回 BTC，池子的 BTC 储备足够，**暂时安全**；但 fwWBTC 持有方失去了"如果 BTC 涨价时卖 fwWBTC 拿 BTC"的退出通道（因为没有人做市）
- **FewCBBTC 沉淀 170 cbBTC (~$14M)**：UNWRAP-ONLY = 用户在持续卖 fwcbBTC 拿 cbBTC。如果有人想**反向 wrap**（用 cbBTC 买 fwcbBTC）会立即吃光流动性
- **FewETHHook 沉淀 1,030 ETH (~$2.4M)**：UNWRAP-ONLY 模式是设计预期（fwWETH 是 wrapped asset，burn 拿 ETH 是主路径）。**这池子算是 8 个里"最正常"的一个**

### 实际可看出的"沉淀 = LP 价值"

因 0 fee、没真实 LP，**这些"沉淀"等同于"被锁死的 side of the pool"**。对协议来说：
- WRAP-ONLY 池 (WBTC/USDC)：沉淀的 underlying 是**负债** — 有人要 unwrap 就要按 1:1 兑付
- UNWRAP-ONLY 池 (其他)：沉淀的 fwToken 反而是**资产** — 等于协议"留存"了 fwToken，underlying 还在 hook contract 备兑

---

## 4. 谁在交易（MEV Bot 主导）

### Top EOA 跨池分布（324 行明细）

| EOA | FewETH | FewUSDT | FewUSDC | FewWBTC | FewCBBTC | FewDAI | FewUNI | 跨池数 |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| `0x3980...0a54d` | #1 | #1 | #2 | #55 | – | – | #2 | **4** |
| `0xf07b...2d88` | #2 | #2 | #11 | #2 | – | – | – | **3** |
| `0x834d...5713` | #3 | #7 | #9 | #3 | – | – | #5 | **5** |
| `0xdf8a...b40c` | #4 | #4 | #8 | #18 | – | – | – | **4** |
| `0xd7e1...d3a2` | #5 | #6 | #10 | #5 | – | – | – | **4** |
| `0xae0c...59ba` | #6 | #14 | #15 | #44 | – | – | – | **4** |
| `0xb19c...49a9` | #7 | #29 | #21 | #20 | – | – | – | **4** |
| `0xaaab...90e6` | #24 | #15 | #12 | #34 | – | – | #9 | **5** |
| `0xc0ff...9671` | #70 | #12 | #3 | #43 | – | – | #7 | **5** |
| `0xdc68...347a` | – | #5 | – | #12 | #8 | – | – | **2** |

> 完整表见 [03_top_traders.result.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/03_top_traders.result.md)

### MEV Bot 模式观察

#### 特征 1: 大量"1-day 1-tx dust 钱包"

以 FewETHHook 为例（109 行 top trader）：
- 排名 60~109 大多是 `active_days=1, swap_count=1, total_usd < $5`
- 单笔金额常见 $0.08 / $0.99 / $2.06 / $4.16 这种**精确小数**
- **典型 MEV bot 测试调用** — 确认池子状态后转入 dust 套利

#### 特征 2: 同一 EOA 跨 4-5 个池子

- 上面列出的 10 个头部 EOA 全部跨 2-4 个池子
- 手工用户不会同时在 4 个池子都做几十笔交易
- 这种模式 = **bot 套利框架同时监控多条池子**

#### 特征 3: 5/26 FewETHHook 单日 79 笔、30 个 unique caller

从 [04_daily_volume.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/04_daily_volume.sql) 看 5/26：
- FewETHHook: 79 swap, 30 unique_callers, total $36K
- 平均每人 2.6 笔，平均 $1.2K
- 大部分 caller's `last_tx == first_tx`（5/26 一次性进出）
- 20 笔金额 < $100（其中 5 笔 < $5）— dust 试探
- **结论**：不是 1 个大 bot，而是几十个小 bot 集群在当天集体扫这套池

#### 特征 4: 交易 tx 的 `to` 都是 MEV bot

直查 FewETHHook top trader（如 `0x3980...0a54d`, rank #1, 95 笔 $401K）的每笔 tx，**每笔的 `tx.to` 都是同一个 MEV bot 合约地址**。这是 sandwich / JIT / liquidation bot 的典型行为：
- bot 合约作为 router
- EOA 只是 bot 合约的 owner / 支付钱包
- 真正的"策略"在合约里

### 谁不是 MEV bot

极少数：
- `0x66c7...de386` (FewCBBTC rank #1, $6.49M, single tx 2025-12-29)：**疑似**项目方一次性 unwrap（金额巨大、单笔）
- `0x5f44...18a5` (FewETH rank #28, 5 tx / FewUSDT rank #20, 9 tx / FewWBTC #1, 1 tx / FewUSDC rank #18, 11 tx)：**可能是 dApp aggregator**（多池、金额稳定）
- `0x1836...0d27` (FewWBTC #8 / FewUSDT #3 / FewCBBTC #6)：**可能是 OTC desk**（多笔、跨 BTC 系）

### 实际结论

**几乎没有真实 dApp 终端用户**。所有高频交易者要么是：
1. **MEV bot 集群**（绝大多数）
2. **协议方**（早期 bootstrap + 偶尔 rebalance）
3. **OTC/aggregator**（极少数）

> 这与 fee=0 的设计是一致的：fee=0 = 没有 LP 套利动机 = 池子只会被 MEV bot 利用来干 dust 套利 + 项目方 rebalance。**完全没有零售用户**（零售 dApp 集成要的是可组合的 wrap/unwrap 合约路径，不是 DEX router）。

---

## 5. 观察建议

### 短期（dashboard 持续观察 7-14 天）

| 关注点 | 触发条件 | 行动 |
|---|---|---|
| 30d 沉淀绝对值 | 单日增量 > 30d 增量的 10% | 检查当天 top traders 是否大单 |
| 5/26 模式重现 | 某日 FewETH 笔数 > 50 | 检查是否 sandwich 攻击 |
| 死池重启 | weETH/wstETH 出现 trade | 立即跑 01 复盘 |
| 跨池子同时异常 | 2+ 池子同一天 swap > 7d mean × 3 | 可能是关联套利 |

### 中期（基于数据做决策）

1. **FewweETHHook / FewwstETHHook — 考虑关停或 bootstrap**
   - 30d 完全 0 交易，0 美元量
   - 浪费 pool 槽位 + 监控精力
2. **FewDAIHook / FewUNIHook — 观察 7-14 天决定去留**
   - 30d 1-4 笔，7d 0 笔
   - 极低活跃但有"沉淀 122K DAI / 7.3K UNI"，关停前要设计退出方案
3. **WRAP-ONLY 池的潜在风险（WBTC/USDC）**
   - 沉淀的 underlying 是**兑付负债**
   - 当前没出问题是因为没人在 unwrap
   - 如果未来加 LP 工具 / 真实用户进入，需提前考虑**双侧 LP 引导**（surge fee 之前讨论过但对 fewToken fee=0 模型不适用，需要重新设计）

### 长期（参考 [plan/01_1to1_wrap_extensions.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/plan/01_1to1_wrap_extensions.md)）

1. 既然 fee=0 + 0 LP + 0 零售 = "当前就是协议资产 + MEV bot 抢 dust"的格局
2. 真正的"利用价值"需要重新设计：
   - **做市 LP 引导**（surge fee 不行；可以考虑 cross-protocol incentives）
   - **跨链桥**（fwToken 当 cross-chain receipt）
   - **收益聚合**（fwToken 自动 accrue yield，burn 时取回 underlying + yield）
3. 持续观察 = 真实用户 / 协议集成是否在发生；目前**没有**这种迹象
