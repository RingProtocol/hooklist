# WETH Hook

> **地址**: [0x57991106cb7aa27e2771beda0d6522f68524a888](https://etherscan.io/address/0x57991106cb7aa27e2771beda0d6522f68524a888)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | WETH Hook |
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

A Uniswap v4 hook that enables seamless ETH/WETH wrapping and unwrapping within v4 pools at a 1:1 ratio. It intercepts swaps to deposit or withdraw ETH from the WETH contract in-flight, supporting both exact input and exact output swaps, while blocking liquidity operations since the pool serves purely as a conversion mechanism.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
