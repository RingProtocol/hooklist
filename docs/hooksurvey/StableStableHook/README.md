# StableStableHook

> **地址**: [0x4509b7eb3f9641226804fea4976963435d1c6080](https://etherscan.io/address/0x4509b7eb3f9641226804fea4976963435d1c6080)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | StableStableHook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeInitialize`, `beforeSwap`

## 属性

`dynamicFee=True` `swapAccess=none`

## 功能描述

Dynamic fee hook for stable/stable pools that adjusts LP fees based on price deviation from a configurable reference price. Fees decay exponentially when the pool price is outside the optimal range, incentivizing arbitrage back to peg while charging reduced fees for stabilizing swaps.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
