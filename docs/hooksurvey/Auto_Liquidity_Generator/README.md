# Auto Liquidity Generator

> **地址**: [0x5725dF570e0008997daCef46bC179bbFc4D125cc](https://etherscan.io/address/0x5725dF570e0008997daCef46bC179bbFc4D125cc)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Auto Liquidity Generator |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeInitialize`, `afterAddLiquidity`, `afterRemoveLiquidity`, `beforeSwap`, `afterSwap`, `beforeSwapReturnsDelta`, `afterSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

Collects configurable buy and sell taxes (in WETH) on every swap. Once accumulated fees reach a configurable threshold, deducts a platform fee (20–50% of the accumulated amount) sent to a designated collector, then uses the remainder to buy the paired token and add full-range protocol-owned liquidity. Residual tokens after liquidity addition are burned.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
