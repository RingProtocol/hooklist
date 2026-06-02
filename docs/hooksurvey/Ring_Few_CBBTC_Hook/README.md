# Ring Few CBBTC Hook

> **地址**: [0x8347b7a3807c681513d2b51b8223e59aa16a2888](https://etherscan.io/address/0x8347b7a3807c681513d2b51b8223e59aa16a2888)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Ring Few CBBTC Hook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeInitialize`, `beforeAddLiquidity`, `beforeSwap`, `beforeSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

Enables atomic 1:1 wrapping and unwrapping between an ERC20 token and its Few-wrapped equivalent within Uniswap v4 swaps, intercepting beforeSwap to perform the wrap/unwrap and returning the delta directly without going through the pool AMM.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
