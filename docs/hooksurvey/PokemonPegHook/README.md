# PokemonPegHook

> **地址**: [0x47dc5827e85f8b63a0b79dfe92e13463eb680440](https://etherscan.io/address/0x47dc5827e85f8b63a0b79dfe92e13463eb680440)
> **链**: Ethereum (chainId=1)
> **部署方**: `0xE20B8921058B116758cfdE5552967C67e70F7b47`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | PokemonPegHook |
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

Pokémon Peg ($pPEG) v4 hook. Mints NFT fragment metadata (one Pokémon per fragment) on every buy, proportional to pPEG received. Resolves the recipient address from hookData (20- or 32-byte) or falls back to tx.origin for contract callers. Calls start() on the token on first liquidity addition and randomises the RNG seed on each afterSwap.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
