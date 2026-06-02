# TokenWorks Hook v2

> **地址**: [0xbd15e4d324f8d02479a5ff53b52ef4048a79e444](https://etherscan.io/address/0xbd15e4d324f8d02479a5ff53b52ef4048a79e444)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | TokenWorks Hook v2 |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeInitialize`, `afterAddLiquidity`, `afterSwap`, `afterSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

A Uniswap v4 hook for NFTStrategy trading pools that applies time-decaying buy fees (starting at 99% and decreasing to 10% as blocks accumulate) and a flat 10% sell fee, collecting fees via afterSwap delta returns and distributing them to configured recipients.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
