# TaxStrategyHook

> **地址**: [0xC804Af6EaA8269C71848e114571f2Dd5314C4044](https://etherscan.io/address/0xC804Af6EaA8269C71848e114571f2Dd5314C4044)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: https://github.com/ETFStrategy/etf-strategy-uniswap-v4
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | TaxStrategyHook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`afterSwap`, `afterSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

A revenue-sharing hook that charges 10% fee on all swaps, automatically converting fees to ETH for strategic allocation: 90% to an automated treasury that invests in ETF-candidate tokens, 10% to development fund. Includes automated profit-taking at 10% gains with buyback-and-burn mechanism.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
