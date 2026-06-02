# Ring Few USDT Hook

> **地址**: [0xbadf77d50478b4432ef1f243b9c0bc7869486888](https://etherscan.io/address/0xbadf77d50478b4432ef1f243b9c0bc7869486888)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Ring Few USDT Hook |
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

Wraps and unwraps USDT to/from fewUSDT (Ring Protocol's wrapped token) automatically during swaps in Uniswap v4 pools, performing 1:1 conversions and absorbing the full swap delta via beforeSwapReturnsDelta.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
