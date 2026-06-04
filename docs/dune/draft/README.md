# docs/dune/draft/

临时性 / 探索性的 SQL。**这些不是长期资产**——它们是分析过程中的中间产物。

| 文件 | 备注 |
|---|---|
| `few_all_pools_wrap_unwrap.sql` | 早期版本, 被 `few_all_pools_liquidity.sql` (根目录) 替代 |
| `feweth_wrap_unwrap_analysis.sql` | 早期版本, 分类逻辑写错 (amount0=0 的 bug) |
| `feweth_90d.sql` | 30d/90d 对比尝试, 数据被 `few_all_pools_liquidity.sql` 覆盖 |
| `feweth_daily.sql` | 每日时间序列, 已被 dashboard 04 替代 |
| `fewwbtc_size_distribution.sql` | 分类逻辑写反, throwaway |
| `fewwbtc_trades_sample.sql` | 临时 sample 查询 |
| `dune.sql` | 早期一行版原型 |

## 保留原则

- **保留**：曾经产生过 insight、对应报告里有引用
- **删除**：纯测试 / 输出无价值 / 已被替代

## 清理时机

每 1-2 个月 review 一次。如果某文件在最近 30 天没被读过且无对应报告引用，可以删除。
