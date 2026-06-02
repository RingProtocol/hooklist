# Token Flow Tax Hook (Ethereum)

> **地址**: [0x74803bd586fa5ce3a9ab38b49a7ca633af8700cc](https://etherscan.io/address/0x74803bd586fa5ce3a9ab38b49a7ca633af8700cc)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Token Flow Tax Hook (Ethereum) |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeSwap`, `afterSwap`, `beforeSwapReturnsDelta`, `afterSwapReturnsDelta`

## 属性

`dynamicFee=True` `swapAccess=none`

## 功能描述

A Uniswap v4 hook that applies configurable taxes on TOKEN/ETH swaps, collecting native ETH taxes on both inflows and outflows. Supports multiple tokens sharing one hook, with a configurable owner cut of all taxes collected.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
