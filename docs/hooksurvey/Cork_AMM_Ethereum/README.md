# Cork AMM (Ethereum)

> **地址**: [0x5287E8915445aee78e10190559D8Dd21E0E9Ea88](https://etherscan.io/address/0x5287E8915445aee78e10190559D8Dd21E0E9Ea88)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Cork AMM (Ethereum) |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeInitialize`, `beforeAddLiquidity`, `beforeRemoveLiquidity`, `beforeSwap`, `beforeSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

Cork AMM is a custom Uniswap v4 hook for the Cork Protocol that implements a specialized AMM for depeg-swap token pairs (RA and CT). It replaces the standard Uniswap price curve with its own pricing logic, gates all native liquidity modifications through the hook's own interface, and supports optional flash swaps via a CorkSwapCallback pattern.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
