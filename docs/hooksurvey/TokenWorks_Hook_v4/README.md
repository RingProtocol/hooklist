# TokenWorks Hook v4

> **地址**: [0xe3c63a9813ac03be0e8618b627cb8170cfa468c4](https://etherscan.io/address/0xe3c63a9813ac03be0e8618b627cb8170cfa468c4)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | TokenWorks Hook v4 |
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

A hook for the TokenWorks NFT strategy ecosystem that restricts pool initialization and liquidity addition to the NFTStrategyFactory, and collects a configurable swap fee (default 10%, with a 95% initial buy fee) distributed among the collection owner, a protocol fee address, and PNKSTR token holders.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
