# TaxHook

> **地址**: [0x6fb14025194d3921942B269ba49c988fbD3fC0Cc](https://etherscan.io/address/0x6fb14025194d3921942B269ba49c988fbD3fC0Cc)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | TaxHook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeSwap`, `afterSwap`, `beforeSwapReturnsDelta`, `afterSwapReturnsDelta`

## 属性

`dynamicFee=True` `swapAccess=none`

## 功能描述

Collects configurable buy and sell taxes on swaps involving the boom.fun BOOM token, splitting fees between a global team address and per-pool developer addresses. Overrides LP fees to zero and applies custom basis-point tax rates via beforeSwap (sell-side) and afterSwap (buy-side) delta returns.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
