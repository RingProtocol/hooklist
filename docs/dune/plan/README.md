# docs/dune/plan/

未来发展方向的**研究 / 方案文档**。这里放的应该是：

- 战略分析（"要不要做 X"）
- 方案对比（"X vs Y 哪个更适合我们"）
- 商业 / 协议设计提案
- 未来 3-12 个月路线图

**不放在这里**：
- 当前 bug fix / 临时分析 → 走 `../draft/` 或根目录
- 长期监控 → 走 `../dashboard/`

## 当前文件

| 文件 | 主题 |
|---|---|
| [01_1to1_wrap_extensions.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/plan/01_1to1_wrap_extensions.md) | 1:1 wrap 协议层的 12 种扩展利用方向（Yield-bearing / 跨链桥 / KYC / Settlement 等） |

## 命名约定

`<序号>_<topic>.md` —— 序号按"完成顺序"或"优先级"排。

例如：
- `01_1to1_wrap_extensions.md` ✅
- `02_yield_bearing_wrapper_design.md`（如果做 yield-bearing 详细设计）
- `03_cross_chain_bridge_research.md`

## 状态

每个文件开头应该有状态标记：

```markdown
# 标题
> **状态**: [proposed / researching / decided / in-progress / done]
> **作者**: ...
> **更新日期**: YYYY-MM-DD
```
