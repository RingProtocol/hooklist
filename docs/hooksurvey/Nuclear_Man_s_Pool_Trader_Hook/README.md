# Nuclear Man's Pool Trader Hook

> **地址**: [0x000b70f7cd351f7479d1aa6f1354d32ed8821080](https://etherscan.io/address/0x000b70f7cd351f7479d1aa6f1354d32ed8821080)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Nuclear Man's Pool Trader Hook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`afterInitialize`, `beforeSwap`

## 属性

`dynamicFee=True` `swapAccess=none`

## 功能描述

A dynamic fee hook that adjusts LP fees based on volatility by comparing spot price from a Uniswap V2 pair against an exponential moving average filter — keeping fees low during calm markets and raising them up to 25% during high-volatility periods. It also collects a configurable developer fee on each swap.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
