# Asterix Hook

> **地址**: [0xdad7ea85ff786b389a13f4714a56b1721b56c044](https://etherscan.io/address/0xdad7ea85ff786b389a13f4714a56b1721b56c044)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Asterix Hook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`afterSwap`, `afterSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

A fee-collection hook that takes a configurable percentage of each swap's unspecified output token: for native ETH outputs the fee is forwarded to a treasury, while for ERC-20 outputs it is burned by sending to a dead address. A separate configurable portion is always forwarded to a main treasury.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
