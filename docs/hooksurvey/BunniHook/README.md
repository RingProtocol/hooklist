# BunniHook

> **地址**: [0x00001f3b9712708127b1fcad61cb892535951888](https://etherscan.io/address/0x00001f3b9712708127b1fcad61cb892535951888)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | BunniHook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`afterInitialize`, `beforeAddLiquidity`, `beforeSwap`, `beforeSwapReturnsDelta`

## 属性

`dynamicFee=True` `swapAccess=none`

## 功能描述

Core hook for Bunni v2, a concentrated liquidity protocol on Uniswap v4. Implements a virtual AMM with dynamic fees (TWAP-based + surge detection), am-AMM bidding for LVR/MEV recapture, auto-rebalancing via FloodPlain, and an on-chain price oracle.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
