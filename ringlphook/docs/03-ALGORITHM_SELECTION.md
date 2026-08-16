# 核心算法选择：EMA + 指数惩罚

## 1. 候选方案回顾

从 50+ hook 调研中，有两个算法最适合 RingLPHook：

| 候选 | 核心公式 | 优势 | 劣势 |
|---|---|---|---|
| **StableStableHook** | `fee = base × exp(α × deviation)` | 偏离越大惩罚越狠，公式极简 gas 低 | 必须知道"正确锚定价格"，任意 pair 不适用 |
| **EMADynamicFeeHook** | 30-step 阶梯表 (0.01%→3.00%) | 任意 pair 可用，完全 immutable，带 Anti-JIT | 阶梯式是线性/分段跳跃，对快速偏离反应不够平滑 |

**问题：能不能把两者的优点结合？**

答案是：**能。** RingLPHook 的算法 = EMA 自参考 + 指数惩罚公式。

---

## 2. 为什么不单独用 StableStableHook

### 2.1 锚定依赖问题

StableStableHook 的 deviation 定义：

```solidity
deviation = |currentPrice - REFERENCE_PRICE| / REFERENCE_PRICE
```

- 对 USDC/USDT：REFERENCE_PRICE = 1.0000（合理）
- 对 ETH/USDC：REFERENCE_PRICE = ???（没有"应该值"）
- 对 ETH/UNI：REFERENCE_PRICE = ???（更没有）

**RingLPHook 的目标是"任意 pair"**，不可能为每个 pair 手动配置锚定价格，更不能链上硬编码。

### 2.2 谁来更新锚定价格？

即使初始化了 REFERENCE_PRICE，当市场结构性变化时（如 ETH 从 $3000 涨到 $5000），
- 如果**不更新**：REFERENCE_PRICE 严重失真，deviation 永远很大，fee 永远很高，池子死亡
- 如果**更新**：需要 owner/governance 定期调整，引入中心化风险和治理攻击面

这与 RingLPHook "immutable 核心"的设计哲学冲突。

---

## 3. 为什么不单独用 EMADynamicFeeHook

### 3.1 30-step 阶梯的问题

EMADynamicFeeHook 的 fee 计算：

```solidity
// 伪代码
uint8 tier = min(29, deviation / TIER_WIDTH);  // 0-29 共 30 档
uint24 fee = FEE_TABLE[tier];                   // 查表
```

**问题：阶梯是"硬跳跃"**

| deviation | fee | 问题 |
|---|---|---|
| 0.99% | tier 0 → 0.01% | 差 0.01% 就跳到下一档，不连续 |
| 1.00% | tier 1 → 0.10% | 跳跃 10 倍，套利者会卡边界 |
| 2.99% | tier 2 → 0.30% | 同上 |
| 3.00% | tier 3 → 1.00% | 跳跃 3.3 倍 |

**套利者可预测 fee**：
- 在 tier 边界精准操作，把 deviation 控制在刚好低于跳跃点的位置
- 阶梯函数的"可预测性"本身就是 MEV 攻击面

### 3.2 缺乏 surge 熔断

EMA 是**滞后指标**（by design）：

```
EMA_t = α × currentPrice + (1-α) × EMA_{t-1}
```

- α = 0.1 时，当前价格只影响 10%，历史占 90%
- 闪电贷瞬间把价格砸 5%，EMA 只会缓慢跟上
- 在这"跟上之前"的窗口，套利者可以**低 fee 大套利**

EMADynamicFeeHook 对此没有额外保护。

---

## 4. RingLPHook 的融合算法

### 4.1 核心公式

```solidity
// Step 1: 计算 EMA 偏离度
uint256 deviation = abs(currentSqrtPriceX96 - emaSqrtPriceX96) * 1e18 / emaSqrtPriceX96;

// Step 2: 指数惩罚
// fee = baseFee × exp(α × deviation)
// 在 Solidity 中用近似：exp(x) ≈ 1 + x + x²/2 + x³/6 （对 x < 1 足够精确）
uint256 feeMultiplier = expWad(α * deviation);
uint24 fee = uint24(baseFee * feeMultiplier / 1e18);

// Step 3: 叠加 surge（若处于 surge 期）
if (surgeActive) {
    uint256 surgeMultiplier = expWad(-int256(elapsed) * 1e18 / halfLife);
    uint24 surgeFee = uint24(maxSurgeFee * surgeMultiplier / 1e18);
    fee = max(fee, surgeFee);  // 取动态 fee 和 surge fee 的较大者
}

// Step 4: clamp 到 [MIN_FEE, MAX_FEE]
fee = clamp(fee, MIN_FEE, MAX_FEE);
```

### 4.2 为什么这样组合

| 组件 | 来源 | 解决的问题 |
|---|---|---|
| **EMA** | EMADynamicFeeHook | 自参考，任意 pair 可用，不需要外部锚定 |
| **指数惩罚** | StableStableHook | 偏离越大惩罚越狠，无阶梯边界可预测性问题 |
| **Surge 熔断** | BunniHook | EMA 滞后时的"熔断器"，防闪电贷瞬间套利 |
| **Clamp** | EMADynamicFeeHook | 防止极端情况下 fee 无限膨胀，保证池子不死亡 |

### 4.3 公式行为可视化

假设 baseFee = 0.05% (500)，α = 2.0，MAX_FEE = 3% (30000)：

| 偏离度 | 纯 EMA 阶梯 (30-step) | 纯指数 (无 clamp) | RingLPHook (EMA+指数+clamp) |
|---|---|---|---|
| 0.1% | 0.05% | 0.06% | 0.06% |
| 0.5% | 0.05% | 0.08% | 0.08% |
| 1.0% | 0.10% (跳跃) | 0.15% | 0.15% |
| 2.0% | 0.30% (跳跃) | 0.37% | 0.37% |
| 5.0% | 1.00% (跳跃) | 1.35% | 1.35% |
| 10.0% | 3.00% (封顶) | 3.69% → clamp 到 3.00% | 3.00% |
| 20.0% | 3.00% | 11.06% → clamp 到 3.00% | 3.00% |

**关键差异**：
- EMA 阶梯在 1% 处从 0.05% 跳到 0.10%（套利者会卡在 0.99% 处操作）
- 指数公式是**连续平滑**的，没有可预测的"边界"，套利者无法精准卡位
- Clamp 是**数学安全上限**，防止 `exp()` 溢出到 100%+，但不等于"最优 fee"

### 4.4 分级 MAX_FEE（交易量保护 vs 数学上限）

**问题**：固定 `MAX_FEE = 3%` 在偏离度 20% 时确实防止了"无限膨胀"，但 3% 本身就会驱赶所有交易量。Clamp 防的是"数学溢出"，不防"经济学上的 fee 过高"。

**解决方案**：`MAX_FEE` 随偏离度动态分级

```solidity
uint256 _getMaxFee(uint256 deviation) pure returns (uint24) {
    if (deviation < 2000) {          // < 2%
        return 30000;                  // 3.00%：正常波动，交易量不敏感
    } else if (deviation < 5000) {   // 2% ~ 5%
        return 15000;                  // 1.50%：偏离明显，保留边际交易
    } else {                          // >= 5%
        return 10000;                  // 1.00%：极端行情，保住最后一点流动性
    }
}
```

| 偏离度 | 分级 MAX_FEE | 理由 |
|---|---|---|
| < 2% | 3.00% | 套利空间通常 < 1%，3% 完全覆盖，正常交易量不受影响 |
| 2% ~ 5% | 1.50% | 已进入"下跌"区间，fee 过高会杀死交易量；1.5% 仍足以让大多数套利者无利可图（考虑 gas + 滑点成本 ~0.5-1%） |
| >= 5% | 1.00% | 极端行情。此时 pool 的核心价值不是"赚 fee"，而是"不被套利者进一步掏空"；1% 已足够阻止套利 |

**关键认知**：
- `MAX_FEE` 是**经济优化参数**，不是安全参数
- 极端偏离时，pool 的目标从"最大化 fee 收入"转变为"最小化 LVR + 保留最后一点交易量"
- 即使 fee=1%，对 5%+ 偏离的套利者仍然是"亏本买卖"（套利空间被 gas、滑点、时间风险吃掉）

---

## 5. Anti-JIT：为什么 300 block

### 5.1 JIT 攻击原理

Just-In-Time Liquidity：
1. 套利者看到有利可图的大单（ mempool 里 pending）
2. 在同一 block 内：**addLiquidity** → **swap**（吃差价）→ **removeLiquidity**
3. 套利者不承担任何"持仓风险"，纯粹寄生在 LP 的流动性上

### 5.2 300 block 的逻辑

| 参数 | 选择 | 原因 |
|---|---|---|
| 300 blocks | ~1 小时（Ethereum 12s/block） | 足够覆盖"看到交易→执行→确认"的整个套利窗口 |
| 惩罚方式 | 高 fee | 不禁止撤流动性（ immutable 原则），而是让 JIT 无利可图 |
| 正常 LP | 不受影响 | 提供流动性 >1 小时后正常撤出，fee 正常 |

EMADynamicFeeHook 选择 300 block 是经过验证的参数（已部署在主网），RingLPHook 直接采用。

---

## 6. Directional Fee：为什么 buy/sell 差异化

### 6.1 概念

CustomFeeMEVProtectionHook 的机制：

```solidity
if (swap is buy token0) {
    fee = buyFee;  // e.g., 0.05%
} else {
    fee = sellFee; // e.g., 0.08%
}
```

### 6.2 为什么 RingLPHook 采用

**目标：对抗"单边砸盘"套利**

场景：
- 某鲸鱼在 CEX 砸 ETH，导致 ETH 价格下跌 2%
- 套利者想在 RingLPHook 池子里**卖 ETH**（换 USDC），把价格砸到跟 CEX 一致
- 如果 sellFee > buyFee，套利者的"砸盘成本"更高

**动态调节**：
- 不是固定 buy/sell 差额，而是根据**历史资金流向**动态调整
- 如果过去 100 个 block 净卖出 > 净买入，auto-increase sellFee，decrease buyFee
- 引导套利者"买回"而非"卖出"，帮助价格回归 EMA

---

## 7. 算法选择决策树

```
需要任意 pair 支持？
├── 否 → StableStableHook（简单，但仅限锚定资产）
└── 是 → 需要 immutable？
    ├── 否 → BVCC（功能多但中心化风险）
    └── 是 → 需要 surge 保护？
        ├── 否 → EMADynamicFeeHook（成熟，已验证）
        └── 是 → RingLPHook（EMA+指数+surge，融合方案）
```

---

## 8. 数学严谨性补充

### 8.1 指数近似精度

Solidity 中没有原生 `exp`，需要近似：

```solidity
// Solady 的 expWad：对 |x| < 20 精度足够（误差 < 0.01%）
// 我们的场景：α × deviation < 2.0 × 0.10 = 0.20，远 < 20，精度完全够用
```

### 8.2 EMA 参数选择

| 参数 | 值 | 理由 |
|---|---|---|
| α (平滑因子) | 0.1 (即 1/10) | 新价格权重 10%，历史 90%。太低 = 反应太慢；太高 = 太敏感 |
| 更新频率 | 每次 afterSwap | 最大化数据点，gas 开销 minimal |
| 初始 EMA | initSqrtPriceX96 | 池子初始化时的价格作为起点 |

### 8.3 Surge 参数选择

| 参数 | 值 | 理由 |
|---|---|---|
| SURGE_THRESHOLD | 1% (单 block) | 1 个 block 内价格变 1% = 异常，触发 surge |
| MAX_SURGE_FEE | 3% | 与 EMADynamicFeeHook 上限一致，LP 可预期 |
| halfLife | 300-600s | 5-10 分钟恢复到正常，不长期阻塞交易 |
| autostartThreshold | 1 hour | 若 1 小时无 surge，强制归零，防止陈旧 surge |

---

## 9. 双 EMA 机制（新增）

### 9.1 为什么需要双 EMA？

**单 EMA 的盲区：慢速均匀下跌**

当价格以**匀速、小幅、单向**方式下跌时（如每小时跌 2%，每 block 只跌 0.006%）：

| 问题 | 说明 |
|---|---|
| Surge **不触发** | 单 block 变化 0.006% 远 < 1% 阈值 |
| EMA **紧跟价格** | α=0.1 时，300 个数据点后 EMA ≈ 当前价，deviation ≈ 0 |
| **Fee 始终很低** | 套利者在整个下跌过程中**几乎免费**套利 |
| **LP 损失惨重** | 价格跌了 2%，IL 已发生，但 fee 收入没跟上 |

**这就是单 EMA 的致命盲区**：对"闪电贷瞬间砸盘"有 surge 保护，但对"慢刀子割肉"完全暴露。

### 9.2 双 EMA 设计

```solidity
struct PoolState {
    // 短周期 EMA：反应近期，用于日常波动检测
    uint256 emaShort;       // α = alphaShort (如 0.1)
    
    // 长周期 EMA：反应长期趋势，用于检测慢跌/慢涨
    uint256 emaLong;        // α = alphaLong (如 0.01)
    
    // 两个 α 值 pool 初始化时设定，immutable per pool
    uint256 alphaShort;     // 典型值：0.1 (1e17)
    uint256 alphaLong;      // 典型值：0.01 (1e16)
}
```

**偏离度计算**：

```solidity
function _calculateDeviation(uint256 current, PoolState storage s) 
    internal pure returns (uint256) 
{
    // 短周期偏离：反应近期波动
    uint256 devShort = abs(current - s.emaShort) * 1e18 / s.emaShort;
    
    // 长周期偏离：反应长期趋势（慢跌时这个值很大）
    uint256 devLong = abs(current - s.emaLong) * 1e18 / s.emaLong;
    
    // 取较大者：确保慢跌时 devLong 主导，瞬间砸盘时 devShort + surge 主导
    return devShort > devLong ? devShort : devLong;
}
```

### 9.3 双 EMA 行为对比

场景：1 小时均匀下跌 2%（300 blocks）

| Block | Current | emaShort (α=0.1) | emaLong (α=0.01) | devShort | devLong | 最终 deviation | Fee |
|---|---|---|---|---|---|---|---|
| 0 | 1000 | 1000 | 1000 | 0% | 0% | 0% | 0.05% |
| 50 | 990 | 999 | 1000 | 0.1% | 1.0% | **1.0%** | ~0.15% |
| 100 | 980 | 997 | 999 | 0.3% | 1.9% | **1.9%** | ~0.37% |
| 200 | 960 | 990 | 996 | 1.0% | 3.6% | **3.6%** | ~1.20% |
| 300 | 940 | 980 | 990 | 2.0% | 5.0% | **5.0%** | ~1.80% |

**关键**：
- 单 EMA（只用 emaShort）：300 blocks 后 deviation = 2.0%，fee ≈ 0.37%
- 双 EMA（取 max）：300 blocks 后 deviation = 5.0%（emaLong 滞后），fee ≈ 1.80%
- **Fee 收入提升 5 倍**，显著补偿 LP 的 IL

### 9.4 α 可配置：per-pool 差异化

不同交易对波动特性不同，α 不应一刀切：

| Pair 类型 | 示例 | alphaShort | alphaLong | 理由 |
|---|---|---|---|---|
| **高波动山寨币** | ETH/PEPE | 0.05 | 0.005 | 波动大，EMA 需要更迟钝才能检测"真趋势" |
| **中波动主流币** | ETH/USDC | 0.1 | 0.01 | 平衡，默认值 |
| **低波动稳定币** | USDC/USDT | 0.2 | 0.02 | 波动小，EMA 可以更敏感 |

**实现**：`alphaShort` + `alphaLong` 在 `beforeInitialize` 时通过 `hookData` 传入，部署后 immutable。

**为什么 immutable**：
- 防止治理攻击（恶意改 α 让 fee 体系失效）
- LP 存入前可以审计确认参数
- 若参数不理想，可部署新 pool 迁移

### 9.5 Gas 影响

| 操作 | 单 EMA | 双 EMA | 增加 |
|---|---|---|---|
| `afterSwap` 更新 | 1 SSTORE | 2 SSTORE | ~5,000 gas |
| `beforeSwap` 计算 | 1 次偏离 | 2 次偏离取 max | ~2,000 gas |
| **总计** | ~12,000 | ~19,000 | ~7,000 gas |

**可接受**：v4 标准 swap ~50,000 gas，双 EMA 后 ~69,000 gas（+38%），仍远低于 BVCC 的 80k-100k。

---

*下一篇：[04-ARCHITECTURE.md](04-ARCHITECTURE.md) — RingLPHook 三层模块化架构设计*
