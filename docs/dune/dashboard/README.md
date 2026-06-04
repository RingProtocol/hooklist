# Ring Hooks Dune Dashboard

> **目的**: 长期观察 9 个 Ring FewToken hook pool 的运行状况（计划 7-14 天观察周期）
> **数据源**: Dune (dex.trades + poolmanager_evt_modifyliquidity + Uniswap v4 池元信息 view)
> **刷新**: 每日 Dune 自动执行（用 Dune 的 scheduled queries 或 dashboard refresh）

## 仪表盘组件（4 张表）

| # | SQL 文件 | 标题 | 回答的问题 |
|---|---|---|---|
| 01 | [01_pool_summary.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/01_pool_summary.sql) | **Pool 概览** | 9 个 pool 的 30d/7d 交易量、流动性、活跃度 |
| 02 | [02_token_reserves.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/02_token_reserves.sql) | **Token 余额 / 沉淀矩阵** | 哪个 pool 沉淀了多少 underlying / fwToken，WRAP 还是 UNWRAP 方向 |
| 03 | [03_top_traders.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/03_top_traders.sql) | **Top 交易者** | 每个 pool 的头部 EOA 是谁、活跃天数、行为模式 |
| 04 | [04_daily_volume.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/04_daily_volume.sql) | **每日交易量时间序列** | 每日 wrap/unwrap 美元量，趋势可视化 + 异常告警 |

## Dashboard 容器

- **URL**: https://dune.com/ring_protocol/ring-hook-monitor
- **状态**: 容器已在 Dune UI 手动创建（API 不支持创建 dashboard，只能手动）

## Query ID 映射 (本地)

`[queries.json](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/queries.json)` 记录每个 SQL 文件对应的 Dune query_id。

```json
{
  "01_pool_summary.sql": 1234567,
  "02_token_reserves.sql": 1234568,
  "03_top_traders.sql":   1234569,
  "04_daily_volume.sql":  1234570
}
```

> 第一次：在 Dune UI 把 4 个 query 跑通一次拿到 query_id，填到 `queries.json`。
> 之后：本地改 SQL → 跑 sync 脚本 → Dune 上的 query 自动更新。

## 一键同步到 Dune

```bash
# 1) 只同步 SQL 定义 (默认 medium, 不会触发重跑)
python3 scripts/dune_dashboard_sync.py

# 2) 同步 + 立即触发重跑
python3 scripts/dune_dashboard_sync.py --execute

# 3) 先看 diff, 不真改
python3 scripts/dune_dashboard_sync.py --dry-run
```

输出示例:
```
→ Dashboard: https://dune.com/ring_protocol/ring-hook-monitor
→ SQL dir:   /.../docs/dune/dashboard
→ Map file:  docs/dune/dashboard/queries.json  (4 entries)
→ Mode:      SYNC+EXECUTE

[patch]   01_pool_summary.sql → query 1234567: OK (0.4s, 1823 chars)
[exec]    01_pool_summary.sql → execution_id: 01HXYZ...
[patch]   02_token_reserves.sql → query 1234568: OK (0.5s, 2104 chars)
...
✓ Synced 4/4 queries
  → results will appear in https://dune.com/ring_protocol/ring-hook-monitor (usually <60s)
```

## 在 Dune UI 创建 Dashboard 步骤 (一次性)

> **Dune API 不支持创建 dashboard / 嵌入 visualization**，必须 UI 手建一次。之后所有 SQL 改动走 sync 脚本。

1. 打开 https://dune.com 并登录
2. **New** → **Query**，依次新建 4 个空 query（先粘 `SELECT 1` 占位都行），name 用 `01_pool_summary` / `02_token_reserves` / `03_top_traders` / `04_daily_volume`。从每个 query 的 URL `https://dune.com/queries/<id>` 提取 query_id。
3. 把 query_id 填到 [`queries.json`](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/queries.json)
4. **New** → **Dashboard**，命名为 "Ring Hooks Monitor" (URL slug: `ring-hook-monitor`)
5. 在 dashboard 里点 **Add visualization**，把 4 个 query 嵌入：
   - `01_pool_summary` → **Table** 组件
   - `02_token_reserves` → **Table** 组件
   - `03_top_traders` → **Table** 组件（按 `caller_rank ≤ 20` filter）
   - `04_daily_volume` → **Bar chart** 组件（X=day, Y=total_usd, color=hook_name, facet=action）
6. 跑 `python3 scripts/dune_dashboard_sync.py --execute` 把本地 SQL 推上去 + 触发首次跑

## 关键观察指标

### 01 Pool 概览
- `swap_count_30d = 0` → **dead pool**，建议关停
- `liquidity_event_count > 5` → 池子被多次 rebalance，可能需要持续监控
- `total_volume_30d > $100K` → 健康池子
- `total_fees_30d` 全为 0 → 当前 fee=0 模型没有协议收入

### 02 Token 余额（最关键）
- `token0_net_stranded` 或 `token1_net_stranded` **绝对值持续增长** → 池子失衡加剧
- 当 `|net_stranded| > 池子初始 reserves × 80%` → **触发 rebalance 预警**
- 7 日内 `net_stranded` 增量 > 30d 增量的 50% → **异常加速**（可能有大户在做批量操作）

### 03 Top 交易者
- `caller_rank = 1` 占比 > 50% → **集中度风险**
- `active_days = 1` 但 `swap_count > 50` → **机器人**，需关注
- 同一 EOA 在 3+ pool 都有交易 → 可能是 dApp / aggregator

### 04 每日交易量
- 某日 `total_usd` > 前 7 天 mean × 3 → **异常活动**
- 连续 7 日 0 volume → **dead pool 候选**

## 配套文件

| 文件 | 用途 |
|---|---|
| [01_pool_summary.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/01_pool_summary.sql) | SQL #1 |
| [02_token_reserves.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/02_token_reserves.sql) | SQL #2 |
| [03_top_traders.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/03_top_traders.sql) | SQL #3 |
| [04_daily_volume.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/04_daily_volume.sql) | SQL #4 |
| [../plan/01_1to1_wrap_extensions.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/plan/01_1to1_wrap_extensions.md) | 1:1 wrap 的扩展利用方案 |
| [../few_pools_analysis_report.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/few_pools_analysis_report.md) | 9 pool 现状分析 |
| `../../scripts/dune_run.py` | 跑 SQL + 自动写 result.md |

## 本地运行

```bash
# 跑单个 query + 保存结果到 .result.md
python3 scripts/dune_run.py docs/dune/dashboard/01_pool_summary.sql 01_pool_summary --save

# 跑全部 4 个
for f in docs/dune/dashboard/*.sql; do
  python3 scripts/dune_run.py "$f" "$(basename $f .sql)" --save
done
```

## 已运行结果 (baseline)

| SQL | 结果 |
|---|---|
| 01_pool_summary | [01_pool_summary.result.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/01_pool_summary.result.md) |
| 02_token_reserves | [02_token_reserves.result.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/02_token_reserves.result.md) |
| 03_top_traders | [03_top_traders.result.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/03_top_traders.result.md) |
| 04_daily_volume | [04_daily_volume.result.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/04_daily_volume.result.md) |

## 分析摘要

- [summary.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard/summary.md) — 4 张表的综合分析（交易量、WRAP/UNWRAP 解释、Token 沉淀、MEV bot 观察）

## 观察记录

建议在 [../plan/01_1to1_wrap_extensions.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/plan/01_1to1_wrap_extensions.md) 末尾维护一个 **"观察日志"** 区块，每天记录 dashboard 发现的异常 / 趋势 / 决策。
