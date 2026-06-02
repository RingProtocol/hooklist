# BtcPegHook

> **地址**: [0x31ac1bba3496628a50d4df734bc2c3e82eeb8440](https://etherscan.io/address/0x31ac1bba3496628a50d4df734bc2c3e82eeb8440)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | BtcPegHook |
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

Mints $bPEG fragments to swap recipients on the ETH/bPEG v4 pool. Calls token.start when first liquidity is added (afterAddLiquidity). Resolves the real EOA recipient on each swap (afterSwap) via hookData (20-byte address override) or tx.origin fallback for routers, then calls BtcPeg.mintFragmentsFor to give the buyer one on-chain fragment per whole bPEG bought. Read-only on the swap path otherwise (no fee, no delta).

Token: 0x520d912430dd5728143851034ABbc692686B8d92 (BtcPeg, verified)
Hook:...

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
