# UCatHook

> **地址**: [0x98fa6468c65ec0100cb92c62dc6109236c130440](https://etherscan.io/address/0x98fa6468c65ec0100cb92c62dc6109236c130440)
> **链**: Ethereum (chainId=1)
> **部署方**: `0x0d6ad47259Ab540bEBC78199357FF2a0488F68aa`
> **审计报告**: https://github.com/Thanattt/unicat/blob/main/AUDIT.md
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | UCatHook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`afterAddLiquidity`, `afterSwap`

## 属性

`vanillaSwap=True` `swapAccess=none`

## 功能描述

Custom v4 hook for UniCat — a production v4 hook combined with an ERC-721 NFT collection (888 hard cap) and staking miner on Ethereum mainnet.

Hook capabilities:
- afterAddLiquidity: one-time initialization trigger that calls token.start() on the first liquidity event involving the UCat token
- afterSwap: re-randomizes a global seed used as entropy for on-chain SVG NFT generation when wallets first receive UCat

Integrates with:
- UCat ERC-20 (0x36608E64D5391bF40486EC81886308a6b8bC06a5)
- UC...

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
