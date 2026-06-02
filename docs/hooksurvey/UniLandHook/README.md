# UniLandHook

> **地址**: [0x4832d5009a234a08a28060196a40bfeb35d6c044](https://etherscan.io/address/0x4832d5009a234a08a28060196a40bfeb35d6c044)
> **链**: Ethereum (chainId=1)
> **部署方**: `0x893582aC23341A07C277B0F026D04d7De6F58678`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | UniLandHook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`afterSwap`, `afterSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

UniLand is a 10,000-plot lottery meme coin powered by a Uniswap v4 hook. Each whole $ULand token (1e18) maps 1:1 to a numbered plot in [1..10000] via a lazy Fisher-Yates shuffle inside the ERC20. On every sell, the hook's afterSwap takes 3% of the output ETH, draws a random plot id, and forwards the ETH directly to that plot's owner. Free plots fall back to the treasury. Buys are tax-free. Hook permissions: afterSwap | afterSwapReturnDelta (bottom-14 = 0x44).

Site: https://unilandhooks.fun
X...

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
