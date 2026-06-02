# ENS Wheel Hook

> **地址**: [0xf13bdafb90c79f2201e2ce42010c8ef75fede8c4](https://etherscan.io/address/0xf13bdafb90c79f2201e2ce42010c8ef75fede8c4)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | ENS Wheel Hook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeInitialize`, `beforeAddLiquidity`, `beforeSwap`, `afterSwap`, `afterSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

A Uniswap v4 hook for the ENSWheel protocol that restricts pool initialization and liquidity additions to the ENSWheel factory, and applies a time-decaying buy fee (starting at 95%, decreasing to 10% over time) distributed between the ENS collection engine (80%) and a configurable team address (20%).

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
