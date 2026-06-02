# Kyber

> **地址**: [0x4440854b2d02c57a0dc5c58b7a884562d875c0c4](https://etherscan.io/address/0x4440854b2d02c57a0dc5c58b7a884562d875c0c4)
> **30d 交易量**: $94.39M | **30d Swap 数**: 3756 | **Pool 数**: 75
> **Dune label**: Kyber
> **状态**: _未在 hooklist 收录_

## 1. 概述

Kyber Network 在 Uniswap V4 上的 hook：
- 75 个 pool, 3756 笔 swap, $94.39M 交易量
- 推测为 Kyber 聚合层在 v4 上提供的"统一费率 + 路由优化"池

**项目方**: [Kyber Network](https://kyber.network)

## 2. 收益结构

| 维度 | 推论 |
|---|---|
| 收入来源 | Kyber 聚合协议费用 (swap 费率) |
| 收费方式 | 在 hook 内抽取 v4 标准费率 + 协议分成 |
| 协议收入 | KyberDAO 治理分配 |

## 3. 工作原理（推论）

- Kyber 在 v4 上自营一批"白名单"池子
- 通过 hook 收取额外 protocol fee
- 75 个 pool 表明 Kyber 提供多 token 对的统一费率策略
- 用户从 Kyber 聚合路由接入

## 4. 时序图

```
User          KyberAggregator      KyberHook      PoolManager
 |                  |                  |                |
 |--swapIntent----->|                  |                |
 |                  |  (选最佳路由)    |                |
 |                  |--swap()--------->|                |
 |                  |                  |--beforeSwap---->|
 |                  |                  | (apply Kyber fee)|
 |                  |                  |--afterSwap----->|
 |<--BalanceDelta---|                  |                |
```

## 5. 风险

- 与 Kyber 聚合层绑定
- 单点治理（KyberDAO）
- 中心化排序风险

## 6. 总结

- 75 个 pool 表明 Kyber 已在 v4 上有相当规模
- $94.39M/30d 单 hook 推算单 pool $1.26M/pool
- 适合 Kyber 路由用户
