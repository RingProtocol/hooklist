# 动态费率 Hook 概述

## 1. 什么是 Dynamic Fee

Uniswap v4 允许 hook 在 `beforeSwap` 中通过返回 `OVERRIDE_FEE_FLAG` 动态覆盖池子的 LP fee。这意味着**每一笔 swap 都可以有不同的费率**，由 hook 根据市场状况实时计算。

```solidity
// beforeSwap 返回值中的第三项
return (selector, BeforeSwapDelta.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
```

`dynamicFee = true` 在 hooklist 中表示该 hook **确实使用了这个机制**，而不是用固定费率。

## 2. 为什么需要动态费率

| 场景 | 固定 fee 的问题 | 动态 fee 的解决 |
|---|---|---|
| **MEV / 三明治攻击** | 攻击者利用固定低 fee 获利 | 偏离越大 fee 越高，压缩攻击利润 |
| **LVR（套利者榨取 LP）** | 套利者总能以低 fee 抢先交易 | 高波动时 fee 自动升高，LP 获得补偿 |
| **闪电贷砸盘** | 固定 fee 无法应对瞬间极端行情 | surge 机制瞬间拉高 fee |
| **稳定币脱锚** | 固定低 fee 加速脱锚套利 | 偏离锚定时 fee 升高，减缓脱锚 |
| **低波动时期** | 固定高 fee 赶走正常交易者 | 低波动时 fee 自动降低，吸引交易量 |

## 3. 动态费率的常见算法

### 3.1 EMA 偏离度（推荐，EMADynamicFeeHook 采用）

```
deviation = |currentPrice - emaPrice| / emaPrice
fee = lookupFee(deviation)  // 阶梯或指数映射
emaPrice = emaPrice * (1-α) + currentPrice * α
```

- **优点**：自参考，不需要外部预言机；任意 pair 通用
- **缺点**：对瞬间极端变化反应稍慢（EMA 有滞后）

### 3.2 锚定价格偏离（StableStableHook 采用）

```
deviation = |currentPrice - anchorPrice| / anchorPrice
fee = base * exp(α * deviation)
```

- **优点**：指数惩罚最狠
- **缺点**：必须知道"正确价格"（锚定价），只适合稳定币对

### 3.3 Surge 衰减（BunniHook / Aegis 采用）

```
if (priceChange > threshold) surgeActive = true
surgeFee = maxFee * exp(-ln2 * elapsed / halfLife)
```

- **优点**：对瞬间砸盘反应极快
- **缺点**：通常需要配合其他机制，单独用覆盖面不够

### 3.4 多维复合（BVCC 采用）

```
fee = f(gasPrice, volatility, volume24h, repeatPenalty)
```

- **优点**：维度多，理论上最精细
- **缺点**：过度复杂，参数多 = 攻击面大，误触发风险高

## 4. hooklist 中的 Dynamic Fee Hook 分布

截至当前，hooklist 共有 **68 个** `dynamicFee = true` 的 hook：

| 链 | 数量 |
|---|---|
| base | 26 |
| ethereum | 13 |
| unichain | 9 |
| arbitrum | 8 |
| bnb | 6 |
| optimism | 3 |
| polygon | 2 |
| monad | 1 |

完整列表见 [02-HOOK_SURVEY.md](02-HOOK_SURVEY.md)。

## 5. 选择标准

对于"直接配置到自己池子仓位使用"的场景，选择标准按优先级排序：

| 优先级 | 标准 | 原因 |
|---|---|---|
| **P0** | immutable（无 owner/admin） | LP 敢存钱，不会被改参数收割 |
| **P0** | 源码已验证 | 知道合约到底做什么 |
| **P0** | 任意 pair 通用 | 不受特定 token 限制 |
| **P1** | 不需要 custom swap data | 标准 router 可直接调用 |
| **P1** | swapAccess = none | 任何人可交易，流动性好 |
| **P1** | 代码简单 | 攻击面小，易审计 |
| **P2** | 已多链部署 | 证明合约可靠 |
| **P2** | 有审计 | 额外安全保证 |

按此标准筛选，**EMADynamicFeeHook** 是唯一满足所有 P0 + P1 条件的 hook。详见 [03-EMA_DYNAMIC_FEE_HOOK.md](03-EMA_DYNAMIC_FEE_HOOK.md)。

---

*下一篇：[02-HOOK_SURVEY.md](02-HOOK_SURVEY.md) — 68 个 dynamic fee hook 横向对比*
