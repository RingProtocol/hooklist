# TokenWorks Hook 系列合并调研

> **系列定位**: TokenWorks NFT 策略 / 平台费用类 hook
> **核心机制**: 时间衰减买卖税 + 工厂限定 + ETH/token 池子限制
> **覆盖版本**: v2, v3, v4, v5 (按版本演进)

## 1. 概述

TokenWorks 是 NFT strategy factory 的费用抽取 hook：
- 通过 hook 在 v4 pool 上抽取买卖费
- 买卖税随时间衰减（典型 99% → 10% / 1%）
- 限制只有 NFTStrategyFactory 能创建/添加流动性
- 1% sell tax / 10% sell tax 等不同版本

## 2. 覆盖的 Hook 列表

| 版本 | 名称 | 地址 | 30d 交易量 | Swap 数 | Pool |
|---|---|---|---|---|---|
| v2 | TokenWorks Hook v2 | [0xbd15...e444](https://etherscan.io/address/0xbd15e4d324f8d02479a5ff53b52ef4048a79e444) | $683.88K | 937 | 6 |
| v3 | TokenWorks Hook v3 | [0xd6a4...6444](https://etherscan.io/address/0xd6a45df0c82c9a686ab1e58fb28d8fc0cf106444) | $12.63K | 50 | 1 |
| v4 | TokenWorks Hook v4 | [0xe3c6...68c4](https://etherscan.io/address/0xe3c63a9813ac03be0e8618b627cb8170cfa468c4) | $2.28M | 1167 | 6 |
| v5 | TokenWorks Hook v5 | (hooks/ethereum 收录) | (见 README) | (见 README) | 6 |

## 3. 收益结构

### 3.1 典型费率模型

| 类型 | 起始 | 衰减 | 终止 | 备注 |
|---|---|---|---|---|
| 买入税 (v2/v3) | 99% | 线性衰减 | 10% / 1% | 在 98 blocks 内衰减 |
| 卖出税 (v2/v3) | 10% | 固定 | 10% | 不衰减 |
| 买入税 (v4) | 99% | 线性衰减 | 10% | 默认 10% sell fee |
| 卖出税 (v4) | 10% | 固定 | 10% | (推论) |

### 3.2 收益分配

- 95% 初始化时给 NFT 策略（按 description 默认）
- 剩余归 NFTStrategyFactory / TokenWorks 协议

## 4. 工作原理

### 4.1 关键权限位（典型）

```
beforeInitialize: true   // 校验只有 factory 能创建
beforeAddLiquidity: true // 校验只有 factory 能加流动性
beforeSwap: true         // 收取 buy fee
afterSwap: true          // 收取 sell fee
afterSwapReturnsDelta: true // 通过 delta 抽费
```

### 4.2 核心机制

```
1. Factory 创建池子，调用 hook
   → hook 校验: msg.sender == factory
   → 设置 token-specific config (衰减参数, 税率)
2. 买入 (Buy)
   → beforeSwap 计算 buyTax
   → buyTax 抽走
3. 卖出 (Sell)
   → afterSwap 计算 sellTax (按时间)
   → sellTax 抽走
4. 衰减
   → 随 blocks 累积，buyTax 衰减
   → sellTax 固定
```

### 4.3 关键文件 (v2 源码)

- `src_hooks_TokenWorksHook.sol`
- `src_libraries_FeeCalculation.sol`
- `src_libraries_DecayMath.sol`
- `src_interfaces_INFTStrategy.sol`

## 5. 时序图

```
Factory      PoolManager     TokenWorksHook      User
 |               |                |                |
 |--init pool--->|                |                |
 |               |--beforeInit-->|                |
 |               |  (校验 factory) |                |
 |               |                |                |
 |--addLiq------>|                |                |
 |               |--beforeAddLiq->|                |
 |               |  (校验 factory) |                |
 |               |                |                |
 |               |                |     |--swap()->|
 |               |--beforeSwap--->|                |
 |               |  (buy fee)     |                |
 |               |                |                |
 |               |  (v4 标准 swap) |                |
 |               |                |                |
 |               |--afterSwap---->|                |
 |               |  (sell fee)    |                |
 |               |                |                |
 |               |<--sel, delta---|                |
 |<--BalanceDelta-----------------|                |
```

## 6. 风险

1. **极端起始税 (99%)** 在 v2 早期对买家极不友好
2. **卖税固定 10%** 抑制长期流动性
3. **依赖 NFTStrategyFactory**，如果 factory 出问题整个系列崩
4. **多版本共存**：v2/v3/v4/v5 哪个被主流使用不确定

## 7. 系列特征总结

| 维度 | TokenWorks v2 | TokenWorks v3 | TokenWorks v4 | TokenWorks v5 |
|---|---|---|---|---|
| 起始买税 | 99% | 99% | 99% | (待确认) |
| 起始卖税 | 10% | 10% | 10% | (待确认) |
| 30d 交易量 | $683.88K | $12.63K | $2.28M | (待确认) |
| Pool 数 | 6 | 1 | 6 | 6 |
| 收益分配 | NFT strategy 95% | 同 v2 | 同 v2 | 同 v2 |

## 8. 总结

TokenWorks 系列是 **"高税率 + 快速衰减"** 的 launchpad 风格 hook：
- 早期抽重税保护 launch
- 后期衰减到合理水平
- 收益归 NFT strategy 协议
- v2/v4 比较活跃，v3/v5 较少使用
- 适合"创作者经济" + "NFT 策略"双层业务
