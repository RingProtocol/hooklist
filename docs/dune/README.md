# docs/dune/ — Dune SQL & 分析文档

Ring Protocol 链上数据分析 + 监控的工作区。

## 目录结构

| 目录 | 用途 | 内容 |
|---|---|---|
| **[dashboard/](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/dashboard)** | **长期监控的 dashboard** | 4 张固定 SQL (pool summary / token reserves / top traders / daily volume) + README |
| [plan/](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/plan) | **未来发展的研究/方案文档** | 1:1 wrap 协议的 12 种扩展利用方向 (P0~P3 路线图) |
| [draft/](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/draft) | **临时性 SQL** (探索/调试) | superseded 的早期 SQL、错误的 size_distribution 等 |
| *(根目录)* | **关键分析报告** | 2 篇阶段总结 (9 pool 现状、FewETHHook 深度) |

## 根目录文件清单

根目录只保留 **2 篇阶段总结报告** + 本 README。其它 SQL 已全部归类到 `dashboard/` (长期监控) 或 `draft/` (临时探索)。

### 分析报告

| 报告 | 主题 |
|---|---|
| [few_pools_analysis_report.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/few_pools_analysis_report.md) | 9 pool 现状 + WRAP/UNWRAP 方向分类 + 沉淀矩阵 (主报告) |
| [feweth_analysis_report.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/feweth_analysis_report.md) | FewETHHook 深度数据 (第一版分析, 已被新报告覆盖) |

## 工具脚本

[scripts/dune_run.py](file:///Users/alexla/code/ringprotocol/hooklist/scripts/dune_run.py) — 跑 SQL + 自动保存结果到 `<name>.result.md`

```bash
python3 scripts/dune_run.py docs/dune/dashboard/01_pool_summary.sql --save
```
