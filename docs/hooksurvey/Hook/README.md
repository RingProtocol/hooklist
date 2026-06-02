# Hook

> **地址**: [0xe48b1ce2fc24365d29bfb4081ac9924965cb58c8](https://etherscan.io/address/0xe48b1ce2fc24365d29bfb4081ac9924965cb58c8)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Hook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`afterInitialize`, `beforeAddLiquidity`, `beforeSwap`, `afterSwap`, `beforeSwapReturnsDelta`

## 属性

`requiresCustomSwapData=True` `swapAccess=governance`

## 功能描述

Prices swaps on an exponential bonding curve (K × (1 -
   e^(-eth/S))) instead of AMM, charging a dual-phase tax — 0.2% with 1 ETH buy 
  cap in Phase 1, 0.5% uncapped in Phase 2. Locked taxes auto-release as rewards
   to staked NFT holders when circulating supply drops below target. Uses 
  beforeSwapReturnDelta for custom delta accounting and blocks all LP additions 
  via beforeAddLiquidity.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
