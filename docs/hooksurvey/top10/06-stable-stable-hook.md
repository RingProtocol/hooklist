# StableStableHook

> **地址**: [0x4509b7eb3f9641226804fea4976963435d1c6080](https://etherscan.io/address/0x4509b7eb3f9641226804fea4976963435d1c6080)
> **30d 交易量**: $74.42M | **30d Swap 数**: 20418 | **Pool 数**: 1
> **Dune label**: Uniswap
> **审计**: 见 [`hooks/ethereum/0x4509b...c6080.json`](file:///Users/alexla/code/uniswap/hooklist/hooks/ethereum/0x4509b7eb3f9641226804fea4976963435d1c6080.json)
> **源码**: [`/Users/alexla/code/uniswap/hooklist/.sources/0x4509b7eb3f9641226804fea4976963435d1c6080/`](file:///Users/alexla/code/uniswap/hooklist/.sources/0x4509b7eb3f9641226804fea4976963435d1c6080/)

## 1. 概述

StableStableHook 是 Uniswap 团队官方提供的 **稳定币 / 稳定币对专用 hook**：
- 单 pool, 大量 swap (20418)
- 30d $74.42M，典型稳定币交易量
- `dynamicFee: true`, `swapAccess: none`

## 2. 收益结构

| 维度 | 说明 |
|---|---|
| 收入来源 | **LP 费** (动态费率) |
| 费率 | 根据价格偏离参考价程度动态调整 |
| 偏离参考价 | 费率指数级增长 |
| 协议分成 | 标准 v4 protocol fee 配置 |

### 2.1 动态费率机制

- 参考价: pool 初始化时记录的"最优价格"
- 当价格偏离参考价时: 费率 = base × exp(α × deviation)
- 偏离越大，费率越高，抑制套利
- 价格回到最优: 费率 = base（最低）

## 3. 工作原理

### 3.1 关键权限位

```
beforeInitialize: true  // 校验池子参数
beforeSwap: true        // 计算动态费率
```

`afterSwap`、`afterInitialize` 等都没启用，所以 hook 行为简单。

### 3.2 beforeSwap 流程

```
1. 读取 pool.slot0() 获取当前价
2. 计算 priceDeviation = |log(currentPrice / referencePrice)|
3. fee = baseFee × exp(α × priceDeviation)
4. 通过 return uint24(fee) 覆盖 v4 默认费率
5. v4 按覆盖后费率收取 LP 费
```

### 3.3 关键文件

- `src_stable_StableStableHook.sol`: 主合约
- `src_stable_base_FeeConfiguration.sol`: 费率配置基类
- `src_stable_libraries_FeeCalculation.sol`: 费率计算库
- `src_stable_interfaces_IFeeConfiguration.sol`, `IStableStableHook.sol`

## 4. 时序图

```
User           PoolManager        StableStableHook
 |                  |                     |
 |--swap()--------->|                     |
 |                  |--beforeSwap()------>|
 |                  |                     |
 |                  |  (读取 slot0,       |
 |                  |   计算 deviation,   |
 |                  |   算 fee)           |
 |                  |                     |
 |                  |<--selector, ZERO, feeOverride---|
 |                  |                     |
 |                  | (按 feeOverride 收取 LP 费)
 |                  |                     |
 |<--BalanceDelta---|                     |
```

## 5. 风险

1. **参考价陈旧**：长时间无 swap 时参考价可能过旧
2. **alpha 参数敏感**：配置不当会导致费率波动过大或过小
3. **仅适合稳定币对**：非稳定币对会因为价格剧烈波动而费率过高

## 6. 总结

- Uniswap 官方的"稳定币优化版 hook"
- 典型 v4 标准费率机制：base + deviation
- 适合 USDC/USDT、DAI/USDC 等强锚定对
- 收益来自 v4 标准 LP 费 + protocol fee
