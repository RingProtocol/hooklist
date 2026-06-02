# Upeg

> **地址**: [0x10865f8301d46a61Badc726DE44d9D4F00F68440](https://etherscan.io/address/0x10865f8301d46a61Badc726DE44d9D4F00F68440)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: https://github.com/ChainCreators/Upeg/tree/main/upegs_hook
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Upeg |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`afterAddLiquidity`, `afterSwap`

## 属性

`swapAccess=none`

## 功能描述

Allows the deployer to define SVG data and read it using a specified seed. Stores metadata for collectible ERC-20 tokens. Calls start on the configured token when first liquidity is added, and updates randomSeed on swaps.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
