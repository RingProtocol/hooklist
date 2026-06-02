# LaunchHook

> **地址**: [0x8bd422134164f74023308a22ba991ae0412900cc](https://etherscan.io/address/0x8bd422134164f74023308a22ba991ae0412900cc)
> **链**: Ethereum (chainId=1)
> **部署方**: `0x9155F76A8349129abd66406cBbBC7D286E5bb031`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | LaunchHook |
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

LaunchHook is the fee-collection hook used by the Tickr launchpad. It charges a flat 2% fee on every swap (taken from input ETH on buys via beforeSwap and from output ETH on sells via afterSwap) and splits it 50/50 between the token's creator — the holder of the corresponding TickrOwner NFT — and the platform. Fee constants and the creator/platform split are immutable; the only governor action is a one-time setFactory(...) binding.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
