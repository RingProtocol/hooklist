# CustomHook

> **地址**: [0x3a3a9a072ab438335a52E0cF064F7ec91D824080](https://etherscan.io/address/0x3a3a9a072ab438335a52E0cF064F7ec91D824080)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | CustomHook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeSwap`

## 属性

`dynamicFee=True` `upgradeable=True` `swapAccess=none`

## 功能描述

Hook for applying a dynamic (changeable) fee for any pool the hook works with. On each swap, it calls poolManager.updateDynamicLPFee() with an admin-configurable fee rate, and is deployed behind a TransparentUpgradeableProxy.

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
