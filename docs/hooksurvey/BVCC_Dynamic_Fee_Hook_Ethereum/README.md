# BVCC Dynamic Fee Hook (Ethereum)

> **地址**: [0xf9ced7d0f5292af02385410eda5b7570b10b50c4](https://etherscan.io/address/0xf9ced7d0f5292af02385410eda5b7570b10b50c4)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | BVCC Dynamic Fee Hook (Ethereum) |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`afterInitialize`, `beforeSwap`, `afterSwap`, `afterSwapReturnsDelta`

## 属性

`dynamicFee=True` `swapAccess=none`

## 功能描述

An advanced anti-bot Uniswap v4 hook by BlockVenture Chain Capital that dynamically adjusts LP fees based on gas price levels, volatility, and 24-hour pool volume. It applies a repeat-swap penalty to deter bot activity and collects a small hook fee from each swap's output amount.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
