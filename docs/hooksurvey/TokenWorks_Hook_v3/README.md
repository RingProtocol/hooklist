# TokenWorks Hook v3

> **地址**: [0xd6a45df0c82c9a686ab1e58fb28d8fc0cf106444](https://etherscan.io/address/0xd6a45df0c82c9a686ab1e58fb28d8fc0cf106444)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | TokenWorks Hook v3 |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeInitialize`, `afterAddLiquidity`, `afterSwap`, `afterSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

A Uniswap v4 hook by TokenWorks that manages fee collection and distribution for NFT strategy ETH/token pools. It enforces ETH/token-only pool initialization via the factory, applies a time-decaying buy fee (starting at 95% and decreasing to 10% over blocks), and uses afterSwapReturnsDelta to skim fees and distribute them to the protocol, stakers, and collection owners.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
