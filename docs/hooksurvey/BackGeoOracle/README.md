# BackGeoOracle

> **地址**: [0xB13250f0Dc8ec6dE297E81CDA8142DB51860BaC4](https://etherscan.io/address/0xB13250f0Dc8ec6dE297E81CDA8142DB51860BaC4)
> **链**: Ethereum (chainId=1)
> **部署方**: `0x080f08076e8EAdC66006C3CbFEd28a34918A1fA6`
> **审计报告**: https://github.com/RigoBlock/back-geo-oracle/blob/main/audits/33Audits_audit_back_geo_oracle.pdf
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | BackGeoOracle |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeInitialize`, `afterInitialize`, `beforeAddLiquidity`, `beforeRemoveLiquidity`, `beforeSwap`, `afterSwap`, `afterSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

A TWAP oracle hook with built-in backrun protection that records on-chain price observations and automatically executes reverse swaps after large price-impact trades to restore the pool price toward the geometric mean, crediting the original swapper with ERC6909 tokens.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
