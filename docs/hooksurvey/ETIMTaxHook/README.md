# ETIMTaxHook

> **地址**: [0x05388fB8B99B66867f08b2841D6bAaea58B040cc](https://etherscan.io/address/0x05388fB8B99B66867f08b2841D6bAaea58B040cc)
> **链**: Ethereum (chainId=1)
> **部署方**: `0x6f5C1F534f569A1Cd00287c65fC4a0B86BF3c9E3`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | ETIMTaxHook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeSwap`, `afterSwap`, `beforeSwapReturnsDelta`, `afterSwapReturnsDelta`

## 属性

`swapAccess=governance`

## 功能描述

A buy/sell tax hook for ETIM/ETH pools that deducts configurable tax rates from swap input amounts using return deltas, holding collected ETH and ETIM fees in the contract for owner withdrawal or burn.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
