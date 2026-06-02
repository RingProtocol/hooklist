# DeployerTaxHook

> **地址**: [0x990a91c744d50fe05a123a80f5a5a6a966f28088](https://etherscan.io/address/0x990a91c744d50fe05a123a80f5a5a6a966f28088)
> **链**: Ethereum (chainId=1)
> **部署方**: `0x2D3daDF3817bc4e76494Ec52Da48D8978142E6bc`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | DeployerTaxHook |
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

Charges a configurable buy/sell tax (up to 15% hardcap) on exact-input swaps for a single token pool by returning a BeforeSwapDelta, accumulating fees as ERC6909 claim tokens on the PoolManager and draining them to a developer wallet via drainFees().

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
