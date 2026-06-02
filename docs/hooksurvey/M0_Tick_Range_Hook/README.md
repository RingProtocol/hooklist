# M0 Tick Range Hook

> **地址**: [0xde400595199e6dae55a1bcb742b3eb249af00800](https://etherscan.io/address/0xde400595199e6dae55a1bcb742b3eb249af00800)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | M0 Tick Range Hook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeAddLiquidity`

## 属性

`vanillaSwap=True` `swapAccess=none`

## 功能描述

Restricts liquidity provision to a configurable tick range by reverting in beforeAddLiquidity if the position's ticks fall outside the allowed bounds. An authorized manager role can update the tick range.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
