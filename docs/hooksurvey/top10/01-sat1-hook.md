# Sat1 Hook - Sato Style

> **地址**: [0x2a0a30dd78af7698e6f40212b8b8324fce2ee888](https://etherscan.io/address/0x2a0a30dd78af7698e6f40212b8b8324fce2ee888)
> **Dune label**: Sat1 Hook - Sato Style
> **30d 交易量**: $738.40M
> **30d Swap 数**: 37505 | **关联 Pool 数**: 1
> **状态**: _本仓库尚未收录_ (Dune 有交易量但 `hooks/ethereum/` 缺失)

## 1. 概述

Sat1 Hook 是 Sato Style (推测为 Sato.Fi 或类似项目) 在 Uniswap V4 上的"挂单 + 限价单"风格 hook。
- 属于 Top 1 交易量（$738.40M/30d），单 hook 单池
- 推测为 `Mev-Blocker` / `RFQ` 风格的 P2P 撮合 swap

> **注**: 本 hook 当前 `hooks/ethereum/` 仓库没有源码，因此以下分析仅基于 Dune 公开字段和 hook 名称/项目方。

## 2. 收益结构

| 维度 | 推论 |
|---|---|
| 收入来源 | 极可能为零费率 / gas 补贴模式（`Sat1` + 1 个 pool + 37505 swaps） |
| 收费方式 | 多为 RFQ 模式，由 off-chain relayer 撮合 |
| 协议收入 | 取决于 Sato Style 商业模型，通常是 spread 而非手续费 |

## 3. 工作原理（推论）

```
User → Sato Relayer → 链下撮合 → 链上 Swap (via hook)
                              ↘ 内部转账 ETH/Token
```

- `Sat1` 暗示 v1 RFQ 撮合合约
- 单 pool 表明交易双方都在同一 token pair 内
- 大量 swaps (37505/30d) 进一步证明这是高频撮合合约

## 4. 时序图

```
User         Sat1 Relayer    Sat1 Hook     PoolManager
 |                |              |              |
 |--quoteReq()-->|              |              |
 |                |--lookup best price          |
 |                |              |              |
 |<--quote-------|              |              |
 |                |              |              |
 |--swap(quote)->|              |              |
 |                |              |--beforeSwap->|
 |                |              | (校验 RFQ id)|
 |                |              |--afterSwap-->|
 |<--BalanceDelta-|              |              |
```

## 5. 风险

- **依赖单一链下 relayer**：可能存在中心化风险
- **未在 hooklist 收录**：源码未审计
- **合约升级路径不透明**

## 6. 建议

下一步可以下载此 hook 源码查看其 `getHookPermissions()` 和 `getHookFees()`。
