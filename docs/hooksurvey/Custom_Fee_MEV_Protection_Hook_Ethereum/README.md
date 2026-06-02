# Custom Fee MEV Protection Hook (Ethereum)

> **地址**: [0xd5770936a6678353f1b17c342b29c4416b029080](https://etherscan.io/address/0xd5770936a6678353f1b17c342b29c4416b029080)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Custom Fee MEV Protection Hook (Ethereum) |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`afterInitialize`, `beforeSwap`

## 属性

`dynamicFee=True` `swapAccess=none`

## 功能描述

A Uniswap v4 hook for TOKEN/ETH and TOKEN/WETH pools that applies configurable directional buy/sell fee overrides and optional anti-MEV protections including blacklisting, one-trade-per-block enforcement, cooldown periods, and maximum sell amount limits.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
