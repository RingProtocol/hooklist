# Action Hook

> **地址**: [0x00bbc6fc07342cf80d14b60695cf0e1aa8de00cc](https://etherscan.io/address/0x00bbc6fc07342cf80d14b60695cf0e1aa8de00cc)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Action Hook |
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

Captures a configurable basis-point fee from BUX/ETH pool swaps, splitting proceeds between an action funding contract (for hourly and daily rewards) and a dev fee splitter via beforeSwap and afterSwap return deltas.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
