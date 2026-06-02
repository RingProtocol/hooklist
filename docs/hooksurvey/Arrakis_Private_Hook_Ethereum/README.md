# Arrakis Private Hook (Ethereum)

> **地址**: [0xf9527fb5a34ac6fbc579e4fbc3bf292ed57d4880](https://etherscan.io/address/0xf9527fb5a34ac6fbc579e4fbc3bf292ed57d4880)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Arrakis Private Hook (Ethereum) |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeAddLiquidity`, `beforeSwap`

## 属性

`dynamicFee=True` `swapAccess=none`

## 功能描述

Restricts liquidity additions to authorized Arrakis LP modules for private vaults, and applies per-direction dynamic fee overrides on swaps via the Uniswap v4 LP fee override mechanism.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
