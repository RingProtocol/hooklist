# Ring FewToken 池子 完整数据分析报告 (修正版 v2)

> **范围**: 9 个 FewToken hook 的所有 v4 池子 (Ethereum Mainnet)
> **时间**: 全部历史数据 + 30 天滚动窗口
> **数据源**: Dune (dex.trades + poolmanager_evt_modifyliquidity)
> **数据时间戳**: 2026-06-04
> **配套 SQL**: [docs/dune/few_all_pools_liquidity.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/few_all_pools_liquidity.sql) (saved to [result.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/few_all_pools_liquidity.result.md))

---

## 一、🔴 重要修正 (相对 v1 报告)

> v1 报告我搞错了——是因为 SQL 里 `VALUES` 字面量跟 `dex.trades.maker` 的 `varbinary` 编码不匹配，导致 JOIN 静默失败 → 8/9 池子显示为 0。修正后真实数据如下。

## 二、9 个池子按用途真实分类

**核心发现：池子不是 "8 ghost + 1 active"，而是按 wrap 方向分成 3 类**：

| 类别 | 池子 | 配对 | 总 trade | USD | Wrap | Unwrap |
|---|---|---|---|---|---|---|
| **🟢 WRAP-ONLY**（只在 mint 路径） | FewWBTC | fwWBTC-WBTC | 249 | $21.08M | **249 (100%)** | 0 |
| **🟢 WRAP-ONLY** | FewUSDC | fwUSDC-USDC | 275 | $417K | **275 (100%)** | 0 |
| **🟡 UNWRAP-ONLY**（只在 burn 路径） | FewCBBTC | cbBTC-fwcbBTC | 132 | $14.08M | 0 | **132 (100%)** |
| **🟡 UNWRAP-ONLY** | FewETHHook | ETH-fwWETH | 2339 | $2.38M | 0 | **2339 (100%)** |
| **🟡 UNWRAP-ONLY** | FewUSDT | USDT-fwUSDT | 345 | $850K | 0 | **345 (100%)** |
| **🟡 UNWRAP-ONLY** | FewDAI | DAI-fwDAI | 19 | $122K | 0 | **19 (100%)** |
| **🟡 UNWRAP-ONLY** | FewUNI | UNI-fwUNI | 40 | $29K | 0 | **40 (100%)** |
| **⚫ DEAD** | FewWEETH | wstETH-fwwstETH | 1 | $6 | 0 | 1 |
| **⚫ DEAD** | FewWSTETH | fwweETH-weETH | 0 | $0 | 0 | 0 |

**关键观察**：
1. **每个池子都是"单向专用"**——只有 mint 方向 或 只有 burn 方向，**没有双向套利循环**
2. **WRAP-only 池子** = 用户在 mint 新 fwToken（罕见，需要明确动机）
3. **UNWRAP-only 池子** = 用户在 burn fwToken 拿回 underlying（更常见，通常是赎回/liquidation 路径）
4. **两个 weETH 池子是真正的 dead pool**——1 笔 / 0 笔

## 三、WRAP vs UNWRAP 由什么决定？

`wrapZeroForOne = (underlying_addr < fwToken_addr)`（hook 部署时确定）：

| `wrapZeroForOne` | token0 / token1 | 用户 trade 方向 | 触发 |
|---|---|---|---|
| `true` | underlying / fwToken | zeroForOne=true | **WRAP** |
| `false` | fwToken / underlying | zeroForOne=false | **UNWRAP** |

**如果池子是 WRAP-only** = 用户**主动选择 zeroForOne=true** 的路径
**如果池子是 UNWRAP-only** = 用户**主动选择 zeroForOne=false** 的路径

这说明使用这些池子的人**有明确的"为什么这样用"**，不是随机套利：
- **WRAP-only 用户**：在 mint 新 fwToken（可能是为了某个 dApp 集成、转账、或跨链桥接）
- **UNWRAP-only 用户**：在 burn fwToken（dApp 清算、用户赎回、协议回收）

**没有套利者**——否则会看到 WRAP-UNWRAP 循环。

## 四、Q2 答案：**为什么池子不空？**

每池子都有 2-3 次 ModifyLiquidity 事件 = **bootstrap LP**。看 FewETHHook 的 3 笔：

| 时间 | Δ (虚拟流动性) | 触发者 |
|---|---|---|
| 2025-11-28 | +7,999,999,999,999,999 (~8e15) | `0x748a...1fb3f` |
| 2025-12-05 | +50,000,000,000,000,000,001 (~50 ETH 虚拟流动性) | `0x4f0a...b9a9` |
| 2025-12-17 | -7,999,999,999,999,999 (dust remove) | `0x748a...1fb3f` |

**结论**：
- **每个池子创建时被 bootstrap 了小量 LP**（很可能是 Ring 协议部署脚本自动添加，或 FewToken factory 合约提供）
- **真实"撑住"池子的通常只有 1 个 EOA**（在 FewETHHook 是 `0x4f0a...b9a9`）
- **剩下的池子**：bootstrap LP 量级太小（200K~500K 虚拟流动性），但**也没完全撤**——说明可能是有 owner 权限的初始 LP 在"占位"
- 8/9 池子虽然"没空"，但 bootstrap 量是 50 ETH 等效以下，对大额 swap 仍是 **"无流动性"**（一次 100 ETH 的 swap 就会击穿）

## 五、Q3 答案：**关于 surge fee 建议——你说得对，我之前错了**

让我直接说结论：

> **surge fee 思路不适合 FewToken 池子**——它针对的是"LP 应该有 yield 才能吸引资金"的问题，但 FewToken 的设计前提就是 **fee=0、1:1 wrap**。

**为什么 surge fee 不适用**：

| 维度 | 适用 surge fee 的池子 (如 BunniHook) | FewToken 池子 |
|---|---|---|
| 池子性质 | 波动对 (ETH/USDC) | 1:1 锚定对 (ETH/fwETH) |
| 价格偏离 | 常见（被套利） | 不应该发生（设计上就 1:1） |
| LP 期望 | 收 fee 赚 IL 补偿 | **fee=0，只赚 wrap/unwrap "基础设施价值"** |
| 谁提供 LP | 协议化 LP (Arrakis/Bunni) | **1 个 EOA + bootstrap** |
| 真实需求 | 流动性深度 = 业务增长 | 流动性深度 = "够用就行" |

**为什么没 LP 跟你没关系**（直接回答你）：
- 你 fee=0 = 没有协议收入 = LP 没有任何"为什么要来"的理由
- 当前的 LP 之所以在，是因为 **bootstrap LP** 协议自己塞的，**不是为了赚 fee**
- 引入 surge fee 的"目的"是 **给 LP 一个 yield 来源**——但**你也不收 surge fee**（fee 全给 LP）
- 等于你**白送 LP 一个 yield 工具**——好处是什么？**让更多外部 LP 来**？
- 但**外部 LP 也不会来**：因为 FewToken 池子的 TVL 太浅，几百万美金的 surge fee 收入分给一个匿名 LP 池，APY 还是 0
- 而且**surge fee 会破坏 1:1 wrap**—— fee > 0 后，wrap 路径的用户实际拿到的 fwToken 数量 < 输入的 underlying，**违反了"1:1"承诺**

**真正应该做的**（按重要性）：

1. **明确商业模式**：FewToken 的 LP 是 "protocol infrastructure" 不是 "yield product"。接受这个前提后，不需要 surge fee
2. **如果想加 surge fee**，把它做成**可选的、可关闭的**：
   - 默认 fee=0（保持 1:1）
   - 在 `beforeSwap` 加一个"如果价格偏离 > X%，启用 surge fee" 的逻辑
   - 这样既能保护 1:1 锚定（正常情况下 fee=0），又能在极端情况下保护 LP（被闪电贷砸盘时）
3. **如果想真吸引 LP**：
   - 把 fee 拆成"LP fee + protocol fee"——比如 surge fee 100 bps，LP 拿 80 bps，协议拿 20 bps
   - 这样协议也有收入，LP 也有 yield，形成双向激励
4. **如果什么都不想改**：
   - 那就别卷 LP 了，接受 "1 个匿名 EOA 撑 50 ETH 虚拟流动性" 是当前可接受的运营状态
   - 重点应该是拉用户/集成方，让 wrap/unwrap 量上去（量上去 → 你的 fewToken 协议有 narrative → bootstrap LP 会自动加）

## 六、给 Ring Protocol 的真正建议 (按 ROI 排序)

1. **关停 FewWSTETH / FewWEETH 池子**：1 笔/0 笔交易，长期占 v4 存储 + 未来 multicall 成本
2. **WRAP-only 池子（WBTC, USDC）值得深入研究**：
   - $21M / $417K 体量远超 ETH/fwWETH 的 unwrap 体量
   - 用户在**主动 mint fwWBTC**——这背后是什么 dApp 集成？谁在批量 mint？
   - **如果能搞清楚 WBTC 用户的 mint 动机，可以复制到其他 token**
3. **UNWRAP-only 池子（ETH, USDT, CBBTC, DAI, UNI）**：
   - 体量大 ($17M+)，说明这些 fwToken 在 DeFi 里**有真实使用场景**
   - 关键是：这些 fwToken 在哪些 dApp 里被用作 collateral？unwrap 触发的是 liquidation 还是 redeem？
4. **fee 模型的取舍**：
   - 当前 fee=0 + bootstrap LP = **可工作的 MVP 状态**
   - 想升级到 "protocolized" 模式：fee > 0 + Arrakis-style LP vault
   - 想保持 1:1：fee=0 + bootstrap LP（当前）
   - **不要加 surge fee**——它跟 1:1 wrap 概念冲突

## 七、配套 SQL 文件 + 结果文件

| SQL 文件 | Result 文件 | 用途 |
|---|---|---|
| [few_all_pools_liquidity.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/few_all_pools_liquidity.sql) | [few_all_pools_liquidity.result.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/few_all_pools_liquidity.result.md) | 9 池子全时间 + 流动性聚合 |
| [few_token_pools.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/few_token_pools.sql) | [few_token_pools.result.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/few_token_pools.result.md) | 9 hook → 9 pool_id 映射 |
| [feweth_ml_events.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_ml_events.sql) | [feweth_ml_events.result.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_ml_events.result.md) | FewETHHook 3 笔 ModifyLiquidity |
| [feweth_top_eoas.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_top_eoas.sql) | [feweth_top_eoas.result.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_top_eoas.result.md) | FewETHHook Top EOA |
| [feweth_top_takers.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_top_takers.sql) | [feweth_top_takers.result.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_top_takers.result.md) | FewETHHook Top taker 合约 |
| [feweth_size_buckets.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_size_buckets.sql) | [feweth_size_buckets.result.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_size_buckets.result.md) | FewETHHook 按 ETH 量分桶 |
| [feweth_wrap_unwrap_analysis.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_wrap_unwrap_analysis.sql) | (old SQL, see [feweth_analysis_report.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_analysis_report.md)) | FewETHHook wrap/unwrap 30d 旧版 |

**运行方式**: `python3 scripts/dune_run.py <sql-file> [name] --save`（带 `--save` 自动写到 `<name>.result.md`）
