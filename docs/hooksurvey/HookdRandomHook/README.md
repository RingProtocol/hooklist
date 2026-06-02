# HookdRandomHook

> **地址**: [0x7b9d30379e446b53e135ce060f38bc2b3be8a040](https://etherscan.io/address/0x7b9d30379e446b53e135ce060f38bc2b3be8a040)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | HookdRandomHook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeInitialize`, `afterSwap`

## 属性

`vanillaSwap=True` `swapAccess=none`

## 功能描述

Records a rolling keccak256 seed per ERC3232 token after each swap, combining swap parameters and block context. ERC3232 tokens query this seed for on-chain randomness during token generation. Pool initialization is factory-gated to prevent unauthorized price setting.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
