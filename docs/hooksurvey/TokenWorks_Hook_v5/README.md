# TokenWorks Hook v5

> **地址**: [0x5d8a61fa2ced43eeabffc00c85f705e3e08c28c4](https://etherscan.io/address/0x5d8a61fa2ced43eeabffc00c85f705e3e08c28c4)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | TokenWorks Hook v5 |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeInitialize`, `beforeAddLiquidity`, `beforeSwap`, `afterSwap`, `afterSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

A Uniswap v4 hook for NFT-backed range liquidity pools that validates pool initialization with an NFT collection, restricts liquidity additions to the NFTStrategyFactory, and takes a dynamic swap fee on behalf of NFT strategy holders via afterSwap delta returns.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
