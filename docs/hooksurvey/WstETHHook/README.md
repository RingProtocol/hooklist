# WstETHHook

> **地址**: [0xa88aacf73df2bccfabcfd1e7b597185cac9f2888](https://etherscan.io/address/0xa88aacf73df2bccfabcfd1e7b597185cac9f2888)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: https://github.com/Uniswap/contracts/pull/93
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | WstETHHook |
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

A Uniswap v4 hook that enables seamless wrapping and unwrapping between stETH and wstETH during swaps, applying the dynamic stETH/wstETH exchange rate in beforeSwap and settling token deltas directly with the pool manager. Liquidity additions are blocked; all exchange is handled exclusively through the hook.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
