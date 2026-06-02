# EMADynamicFeeHook

> **地址**: [0x924e5C44c3b82C2C0Ba231Cd0De7B581180E1bC0](https://etherscan.io/address/0x924e5C44c3b82C2C0Ba231Cd0De7B581180E1bC0)
> **链**: Ethereum (chainId=1)
> **部署方**: `0xbE048D30fa1b5144694D33f8bd482D469028Da99`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | EMADynamicFeeHook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`afterInitialize`, `beforeAddLiquidity`, `beforeRemoveLiquidity`, `afterRemoveLiquidity`, `beforeSwap`, `afterSwap`

## 属性

`dynamicFee=True` `swapAccess=none`

## 功能描述

EMA-based dynamic fee hook for Uniswap V4. Calculates swap fees using Exponential Moving Average of price, with 30-step fee schedule (0.01%-3.00%) and 300-block anti-JIT protection via tx.origin. No owner, no admin functions, fully immutable.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
