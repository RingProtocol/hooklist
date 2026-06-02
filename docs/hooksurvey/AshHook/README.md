# AshHook

> **地址**: [0xeBAc1d1a384D3AE1a162fdF30788FcfA228380cc](https://etherscan.io/address/0xeBAc1d1a384D3AE1a162fdF30788FcfA228380cc)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | AshHook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeSwap`, `afterSwap`, `beforeSwapReturnsDelta`, `afterSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

Protocol fee hook for an ASH/ETH pool that captures a configurable 5% trading fee (up to 10%) on both buys and sells, routing collected ETH to a treasury address using beforeSwapReturnsDelta for buy fees and afterSwapReturnsDelta for sell fees.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
