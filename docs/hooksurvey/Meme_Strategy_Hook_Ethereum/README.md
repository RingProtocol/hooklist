# Meme Strategy Hook (Ethereum)

> **地址**: [0x3ba779bad405d9b68a7a7a86ff6916c806a200cc](https://etherscan.io/address/0x3ba779bad405d9b68a7a7a86ff6916c806a200cc)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Meme Strategy Hook (Ethereum) |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeSwap`, `afterSwap`, `beforeSwapReturnsDelta`, `afterSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

A Uniswap v4 hook for the MEMS meme token that collects dynamic asymmetric swap fees (Phase 1: 50%, Phase 2: 10–90%) on ETH↔MEMS swaps, splitting proceeds 80/20 between a strategy contract and treasury. Includes anti-snipe protection that blocks public swaps until trading is activated by the strategy.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
