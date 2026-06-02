# Angstrom

> **地址**: [0x0000000aa232009084Bd71A5797d089AA4Edfad4](https://etherscan.io/address/0x0000000aa232009084Bd71A5797d089AA4Edfad4)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: https://github.com/spearbit/portfolio/blob/master/pdfs/Sorella-Spearbit-Security-Review-October-2024.pdf
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Angstrom |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeInitialize`, `afterInitialize`, `beforeAddLiquidity`, `beforeRemoveLiquidity`, `beforeSwap`, `afterSwap`, `afterDonate`, `afterSwapReturnsDelta`

## 属性

`dynamicFee=True` `requiresCustomSwapData=True` `swapAccess=none`

## 功能描述

Angstrom is a decentralized exchange that takes control of its transaction ordering, preventing value extraction from liquidity providers and traders. By running application-specific auctions, Angstrom internalizes MEV and redirects the extracted value back to users, preventing arbitrage losses and sandwich attacks while reducing trading fees and gas.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
