# LodeHook

> **地址**: [0x8f24193cc75fc64a30a038442bcd622ff4070088](https://etherscan.io/address/0x8f24193cc75fc64a30a038442bcd622ff4070088)
> **链**: Ethereum (chainId=1)
> **部署方**: `0x9849ddA51E40e56998FE269568A7619eA3521cbF`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | LodeHook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeSwap`, `beforeSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

A Uniswap v4 hook that captures top-of-block LVR and routes it through a per-pool splitter

The first swap of each block on an opted-in pool pays an additional premium scaled by `premiumBps`. Subsequent swaps in the same block pay only standard pool fees. A `minAuctionInputSize` floor defeats dust-disarm attacks, sub-economic swaps skip the auction slot without consuming it.

Safety.
- Pause guardian (separate multisig, kills capture globally in one tx)
- Per-pool deactivation
- 24h timelock ...

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
