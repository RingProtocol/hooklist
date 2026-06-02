# Strategic Reserve Hook

> **地址**: [0x6e1babe41d708f6d46a89cda1ae46de95458e444](https://etherscan.io/address/0x6e1babe41d708f6d46a89cda1ae46de95458e444)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Strategic Reserve Hook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeInitialize`, `afterAddLiquidity`, `afterSwap`, `afterSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

Manages fee collection and distribution for Strategic Reserve ETH/token pools, implementing a time-decaying buy fee that starts high (up to 80%) and decreases to a configurable floor (4-10%), with fees distributed to reserve contracts and protocol recipients.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
