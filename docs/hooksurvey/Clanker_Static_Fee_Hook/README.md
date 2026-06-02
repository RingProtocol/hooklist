# Clanker Static Fee Hook

> **地址**: [0x6c24d0bcc264ef6a740754a11ca579b9d225e8cc](https://etherscan.io/address/0x6c24d0bcc264ef6a740754a11ca579b9d225e8cc)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Clanker Static Fee Hook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeInitialize`, `beforeAddLiquidity`, `beforeSwap`, `afterSwap`, `beforeSwapReturnsDelta`, `afterSwapReturnsDelta`

## 属性

`dynamicFee=True` `requiresCustomSwapData=True` `swapAccess=none`

## 功能描述

A Uniswap v4 hook for the Clanker token launchpad that enforces per-pool static LP fees configured at initialization, collects protocol fees on the paired token, and supports optional MEV-protection modules and pool extensions.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
