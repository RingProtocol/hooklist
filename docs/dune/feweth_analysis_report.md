# FewETHHook 数据分析报告

> **Hook**: [0x044301939deb7ca53c4733dd4d9b3bc5ea0c6888](https://etherscan.io/address/0x044301939deb7ca53c4733dd4d9b3bc5ea0c6888)
> **Pool**: [0x7a5a8f5a36a6a2e9961caf6bb047a5a7580d0fe16a532aad93efc596028dfa54](https://etherscan.io/address/0x7a5a8f5a36a6a2e9961caf6bb047a5a7580d0fe16a532aad93efc596028dfa54)
> **fwWETH token**: [0xa250cc729bb3323e7933022a67b52200fe354767](https://etherscan.io/address/0xa250cc729bb3323e7933022a67b52200fe354767)
> **数据时间**: 2026-05-05 ~ 2026-06-04 (30d)
> **数据源**: [dex.trades](https://dune.com/queries) (Dune SQL via `scripts/dune_run.py`)

---

## 一、最关键的发现 ⚠️

> **该 pool 在 30 天 / 90 天内 100% 是 UNWRAP（fwWETH → ETH），零 WRAP（ETH → fwWETH）。**

| 窗口 | UNWRAP 笔数 | WRAP 笔数 | UNWRAP 美元量 | WRAP 美元量 |
|---|---|---|---|---|
| **30 天** | 289 swaps / 295 trades | **0** | $217,047 | **$0** |
| **90 天** | 945 trades | **0** | $620,991 | **$0** |

**这意味着该 hook 的 wrap 路径实际上从未被使用过**。原因很明显——`fwWETH.wrap()` 可以直接调用 token 合约拿到 1:1 包装 ETH 的结果，不需要走 v4 池；只有 **unwrap** 路径（持有 fwWETH 想换回 ETH）才需要这个池子提供 1:1 流动性。

---

## 二、Top 调用者 (30d)

| EOA | Swap 数 | fwWETH 量 | USD | 活跃天数 |
|---|---|---|---|---|
| `0x834d...5713` | 34 | 14.85 | $29,079 | 16 |
| `0xd7e1...a3b2` | 32 | 12.01 | $25,190 | 21 |
| `0xf07b...2d88` | 31 | 21.74 | $47,916 | 15 |
| `0xb19c...499a` | 27 | 4.07 | $8,867 | 13 |
| `0xdf8a...b40c` | 26 | 10.33 | $22,843 | 12 |
| `0xae0c...59ba` | 25 | 11.66 | $23,535 | 14 |
| ... | ... | ... | ... | ... |
| **Top 6 合计** | **175** (60%) | **74.6** (73%) | **$157K** (72%) | — |

**观察**：Top 6 EOAs 占 60% 的笔数和 73% 的 ETH 量，但活跃天数都在 12-21 天之间——**说明是较活跃的散户/小机构用户，不是机器人**（机器人通常活跃天数极少但单日量大）。

---

## 三、Top 触发合约 (Taker)

| Taker 合约 | Swap 数 | fwWETH | USD | 唯一调用者 | 备注 |
|---|---|---|---|---|---|
| **`0x0443...6888` (FewETHHook 自己)** | **149** | 46.45 | $99,437 | 44 | **占 45% 的 USD 量** |
| `0x06cf...f5ef` | 67 | 32.51 | $70,123 | 7 | 未知合约 |
| `0xd226...9f89` | 44 | 15.01 | $29,652 | 6 | 看起来像 EOA |
| `0x163f...56e0` | 20 | 1.06 | $2,184 | 16 | 4 天窗口（5-26~5-29） |
| 其他 6 个 | < 2 | — | < $7K | — | — |

**关键观察**：**hook 自身（`0x0443...6888`）是 #1 taker**，49% 的 swap 是 hook 在调用自己。这跟 hook 的工作机制有关——`dex.trades` 把"hook 解析 delta"这个动作也记成了一笔 trade（实际上 hook 走的是 `poolManager.take()` / `poolManager.settle()` 不是真的 swap）。

---

## 四、笔均规模分布 (散户/大户)

| 桶 | 笔数 | 占比 | ETH 量 | USD | 笔均 USD |
|---|---|---|---|---|---|
| < 0.01 ETH | 23 | 8% | 0.09 | $186 | $8 |
| 0.01–0.1 ETH | 57 | 19% | 2.93 | $6,301 | $111 |
| **0.1–1 ETH** | **193** | **65%** | 45.15 | **$96,460** | $500 |
| 1–10 ETH | 22 | 7% | 54.62 | $114,100 | $5,186 |
| > 10 ETH | 0 | 0% | 0 | $0 | — |

**观察**：
- 65% 的笔数集中在 0.1-1 ETH 桶（**典型散户**）
- 但 **1-10 ETH 桶贡献了 53% 的 USD 量**（少数大单拉高了 volume）
- 完全没有 10+ ETH 的交易——**没有鲸鱼/大机构使用**

---

## 五、按天时间分布

| 特征 | 数值 |
|---|---|
| 平均日 swap | ~10 |
| 中位日 USD | ~$5,000 |
| 单日峰值 | **2026-05-26: 79 swaps / $36,615**（≈平时 7 倍，疑似一次批量操作） |
| 0-swap 日 | 几乎没有（30 天每天都 ≥ 1） |
| wrap_count | **全部 30 天都是 0** |

无明显周期性或时间相关性。

---

## 六、结论 & 给 Ring Protocol 的启示

### 6.1 商业模型现实

- **FewETHHook 的 1:1 ETH↔fwWETH 池本质是"退出门"**——用户持有 fwWETH 时如何换回 ETH。**Wrap 路径完全不需要 pool**（直接调 token 合约）。
- 这跟 BunniHook / StableStableHook 等"fee 抽成型"hook 的商业逻辑完全不同——**这里没有 LP 收益来源**（fee_in_percent = 0）。
- 30 天 $217K 的体量，假设 fee=0，意味着 **LP 完全靠"白干"在做市**，只赚 pool 内 IL 风险补偿（=0）。

### 6.2 真正在使用 hook 的人

- **少数"持有 fwWETH 的人"通过这个池退出到 ETH**
- 散户为主（65% 在 0.1-1 ETH）
- 没有 MEV bot / 套利者（如果有套利会有 WRAP-UNWRAP 循环）
- 也没有聚合器调用（如果有 1inch/Paraswap 进来会看到对应 router 在 Top Taker）

### 6.3 隐藏的 hook 调用模式

**`0x0443...6888` 自身 = 49% taker** 这个反常指标说明：
- `dex.trades` 把 hook 的 `_take` / `_settle` 操作也计为"swap"
- 也就是说，**真正主动发起 unwrap 的"用户"只有约 50% 的 149 = ~70 笔**，剩下 ~220 笔的 taker 是其他合约
- 可能这些合约是 **dApp 集成 fwWETH 作为 collateral** 的 liquidation/rebalance 路径

### 6.4 给 Ring Protocol 的建议

1. **如果 FewETHHook 的"wrap"路径完全没人用**——考虑把 wrap 路径从 pool 中移除（设为禁用），只保留 unwrap 路径；这能省 gas + 简化代码
2. **fee_in_percent = 0 是当前状态**，但如果把 ETH 池的 LP 替换为"单向 only 接受 fwWETH 单边 deposit"，可以避免 IL
3. **类似的 FewUSDC/USDT/DAI 池子大概率也是同构**——wrap 路径无人用，unwrap 才是真正流量来源
4. **如果想要 fee 收益**，考虑学 WETHHook（Uniswap 官方）+ WstETHHook 把 1:1 wrap pool 改成"ETH ↔ wrapped" 的等效路由，但允许其他 dex aggregator 通过这个池来 routing（拿 spread 作为 fee）

---

## 附：使用的 SQL 文件清单

- [feweth_wrap_unwrap_analysis.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_wrap_unwrap_analysis.sql) — 整体 wrap/unwrap 30d
- [feweth_90d.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_90d.sql) — 90d wrap/unwrap 总览
- [feweth_top_eoas.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_top_eoas.sql) — Top EOA 调用者
- [feweth_top_takers.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_top_takers.sql) — Top 触发合约
- [feweth_size_buckets.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_size_buckets.sql) — 按 ETH 量分桶
- [feweth_daily.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_daily.sql) — 按天时间序列
- `scripts/dune_run.py` — Dune API 执行 + 打印表格的工具脚本
