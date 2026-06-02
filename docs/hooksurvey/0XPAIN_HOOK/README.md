# 0XPAIN HOOK

> **地址**: [0x0089938dc53258d2bbbb666043abe812a3c18440](https://etherscan.io/address/0x0089938dc53258d2bbbb666043abe812a3c18440)
> **链**: Ethereum (chainId=1)
> **部署方**: `0xD626EB019226A7B1b7a7F112a378B790A47C4568`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | 0XPAIN HOOK |
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

PokemonPegHook is a Uniswap v4 hook that powers PokemonPeg ($pPEG), an art-coin where every buy mints a unique          on-chain pixel-art NFT fragment to the trader.
                                                                                                                          Hook permissions: afterAddLiquidity + afterSwap.

  Mechanism: on each ETH→pPEG swap, the hook resolves the real recipient (via hookData 20b/32b, with tx.origin fallback
  for EOAs) and mints a deterministic ...

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
