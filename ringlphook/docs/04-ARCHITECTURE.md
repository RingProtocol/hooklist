# RingLPHook 三层模块化架构

## 1. 架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│                         External Actors                          │
│  Trader / Arbitrageur / Normal LP / JIT Attacker / Ring Team    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Uniswap V4 PoolManager                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  initialize  │  │    swap      │  │ addLiquidity │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                 │                  │
│         ▼                 ▼                 ▼                  │
│  ┌──────────────────────────────────────────────────────┐     │
│  │                  RingLPHook Contract                  │     │
│  │  ┌────────────────────────────────────────────────┐  │     │
│  │  │  Layer 3: Surge Protection (Bunni-inspired)   │  │     │
│  │  │  ┌──────────────────────────────────────────┐  │  │     │
│  │  │  │  Layer 2: Dynamic Fee Engine (核心)       │  │  │     │
│  │  │  │  ┌──────────────────────────────────────┐  │  │  │     │
│  │  │  │  │  Layer 1: Anti-MEV / Anti-JIT 基线   │  │  │  │     │
│  │  │  │  └──────────────────────────────────────┘  │  │  │     │
│  │  │  └──────────────────────────────────────────┘  │  │     │
│  │  └────────────────────────────────────────────────┘  │     │
│  └──────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 各层详解

### Layer 1: Anti-MEV / Anti-JIT 基线（必做，低成本高回报）

**目标**：阻止最常见的两类攻击（JIT + 三明治），经济手段为主，不依赖访问控制。

#### 2.1 300-block Anti-JIT

| 项 | 详情 |
|---|---|
| **触发点** | `beforeAddLiquidity` |
| **机制** | 记录 LP 存入时间戳；`beforeRemoveLiquidity` 时若 < 300 blocks，apply JIT penalty fee |
| **Penalty** | 不是禁止撤出，而是让撤出时的 fee 极高（如 3%），使 JIT 无利可图 |
| **正常 LP** | > 300 blocks 后正常撤出，无额外 fee |

**为什么有效**：
- JIT 的核心是"同一 block 内进出"，300 blocks ≈ 1 小时的锁仓完全打破这个逻辑
- 不禁止 = 不引入中心化封锁能力，符合 immutable 原则

#### 2.2 Repeat-Swap Penalty

| 项 | 详情 |
|---|---|
| **触发点** | `beforeSwap` |
| **机制** | 记录 `lastSwapBlock[trader]`；仅当**同 block** 再次 swap 时，fee +50% |
| **Decay** | 跨 block 后自动归零（不同 block = 无惩罚） |
| **为什么** | 同 block 连续 swap 是三明治/循环套利的明确特征；正常用户不会在同一 block 内手动发两笔交易 |
| **误伤控制** | DEX 聚合器（1inch/Paraswap）的 multi-hop 走 router 合约地址，与用户 EOA 地址不同，不会触发 |

**为什么去掉"相邻 block"**：
- 正常 DCA、分批建仓、聚合器拆分都会跨多个 block，不应被惩罚
- 三明治攻击的核心特征是**同一 block 内** front-run + back-run，跨 block 反而无法构成有效三明治（价格已被他人改变）

#### 2.3 Directional Fee

| 项 | 详情 |
|---|---|
| **触发点** | `beforeSwap` |
| **机制** | Buy vs Sell 差异化费率；根据历史净资金流向动态调节 |
| **目的** | 对抗"单边砸盘"套利，引导反向操作帮助价格回归 |

#### 2.4 Max Sell Limit

| 项 | 详情 |
|---|---|
| **触发点** | `beforeSwap` |
| **机制** | 单笔 sell 量 ≤ pool 流动性的 X%（如 1%） |
| **为什么** | 防止鲸鱼单次砸盘，迫使大单拆分成多笔，每笔都付更高 fee |

---

### Layer 2: Dynamic Fee Engine（核心）

**目标**：根据价格偏离度自动调节 fee，偏离越大 fee 越高。

#### 2.1 状态结构（per pool）

```solidity
struct PoolState {
    // 双 EMA：短周期（反应近期）+ 长周期（反应长期趋势）
    uint256 emaShort;              // 短周期 EMA，α = alphaShort
    uint256 emaLong;               // 长周期 EMA，α = alphaLong
    uint256 alphaShort;            // 短周期平滑因子 (e.g., 0.1 = 1e17)
    uint256 alphaLong;             // 长周期平滑因子 (e.g., 0.01 = 1e16)
    uint256 lastEmaUpdateBlock;    // 最后更新区块
    
    // Fee 相关
    uint24 baseFee;               // 基础费率 (e.g., 500 = 0.05%)
    uint24 currentFee;            // 当前生效费率（缓存）
    
    // Surge 相关
    uint256 lastSurgeTimestamp;   // 最后 surge 触发时间
    uint24 lastSurgeFee;          // surge 触发时的 fee 值
    bool surgeActive;             // 是否处于 surge 期
    
    // Directional 相关
    int128 netFlow;               // 净资金流向 (buy - sell)
    uint256 lastFlowUpdate;       // 最后更新净流向的时间
}
```

#### 2.2 双 EMA 更新（afterSwap）

```solidity
function _updateEMA(PoolId id, uint256 currentSqrtPriceX96) internal {
    PoolState storage s = poolStates[id];
    
    uint256 blocksElapsed = block.number - s.lastEmaUpdateBlock;
    if (blocksElapsed == 0) return;  // 同 block 不重复更新
    
    // 更新短周期 EMA：α = alphaShort，反应近期波动
    s.emaShort = (
        currentSqrtPriceX96 * s.alphaShort + 
        s.emaShort * (1e18 - s.alphaShort)
    ) / 1e18;
    
    // 更新长周期 EMA：α = alphaLong，反应长期趋势
    // alphaLong 更小，所以 emaLong 更"迟钝"，滞后更大
    s.emaLong = (
        currentSqrtPriceX96 * s.alphaLong + 
        s.emaLong * (1e18 - s.alphaLong)
    ) / 1e18;
    
    s.lastEmaUpdateBlock = block.number;
}
```

#### 2.3 Fee 计算（beforeSwap）

```solidity
function _calculateFee(PoolId id, uint256 currentSqrtPriceX96, bool isBuy) 
    internal 
    view 
    returns (uint24 fee) 
{
    PoolState storage s = poolStates[id];
    
    // 1. 双 EMA 偏离度：取短周期和长周期的较大者
    // 短周期偏离：反应近期波动（瞬间砸盘时大）
    uint256 devShort = _calcDeviation(currentSqrtPriceX96, s.emaShort);
    // 长周期偏离：反应长期趋势（慢跌时 emaLong 滞后大，devLong 大）
    uint256 devLong = _calcDeviation(currentSqrtPriceX96, s.emaLong);
    // 取较大者：确保无论"快跌"还是"慢跌"都能捕捉
    uint256 deviation = devShort > devLong ? devShort : devLong;
    
    // 2. 指数惩罚
    uint256 feeMultiplier = _expApprox(ALPHA * deviation);
    uint24 dynamicFee = uint24(s.baseFee * feeMultiplier / 1e18);
    
    // 3. 叠加 surge（检测也使用双 EMA 偏离度）
    if (s.surgeActive) {
        uint256 elapsed = block.timestamp - s.lastSurgeTimestamp;
        uint256 surgeMultiplier = _expApprox(
            -int256(elapsed) * 1e18 / int256(SURGE_HALF_LIFE)
        );
        uint24 surgeFee = uint24(MAX_SURGE_FEE * surgeMultiplier / 1e18);
        dynamicFee = dynamicFee > surgeFee ? dynamicFee : surgeFee;
    }
    
    // 4. 方向性调节
    if (!isBuy && s.netFlow < 0) {
        // 净卖出多 → sell fee 更高
        dynamicFee = uint24(dynamicFee * SELL_PREMIUM / 1e18);
    } else if (isBuy && s.netFlow > 0) {
        // 净买入多 → buy fee 更高
        dynamicFee = uint24(dynamicFee * BUY_PREMIUM / 1e18);
    }
    
    // 5. Clamp with tiered MAX_FEE
    uint24 maxFee = _getMaxFee(deviation);  // < 2%→3%, 2-5%→1.5%, >=5%→1%
    fee = _clamp(dynamicFee, MIN_FEE, maxFee);
}
```

---

### Layer 3: Surge Protection（Bunni-inspired，纯 on-chain）

**目标**：当价格**突变**（非缓慢偏离）时，立即把 fee 拉到顶，然后指数衰减恢复。

#### 3.1 触发条件（afterSwap）

```solidity
function _checkSurge(PoolId id, uint256 currentSqrtPriceX96) internal {
    PoolState storage s = poolStates[id];
    
    // Surge 检测使用短周期 EMA（反应"瞬间偏离"）
    // 长周期 EMA 不适合 surge，因为它本身就是"滞后"的
    uint256 priceDelta = _calcDeviation(currentSqrtPriceX96, s.emaShort);
    
    // 单 block 内偏离 > 阈值 → 触发 surge
    if (priceDelta > SURGE_THRESHOLD) {  // e.g., 1%
        s.surgeActive = true;
        s.lastSurgeTimestamp = block.timestamp;
        s.lastSurgeFee = MAX_SURGE_FEE;  // e.g., 3%
    }
    
    // 自动衰减：超过 autostartThreshold 强制归零
    if (block.timestamp >= s.lastSurgeTimestamp + SURGE_AUTOSTART_THRESHOLD) {
        s.surgeActive = false;
    }
}
```

#### 3.2 衰减曲线

```
Fee
  │
3%├────────╮
  │        ╲
  │         ╲
  │          ╲
  │           ╲
  │            ╲
  │             ╲
0.5%├───────────╲───────
  │              ╲
  │               ╲
  │                ╲
  │                 ╲
  └───────────────────────→ Time
    0    5min   15min  30min  1hr
    │     │      │      │     │
   触发   halfLife  3×    6×   autostart
```

#### 3.3 为什么 EMA + surge 是互补的

| 场景 | EMA 反应 | Surge 反应 | 结果 |
|---|---|---|---|
| 缓慢偏离（1%/小时） | ✅ 平滑跟随 | ❌ 不触发 | EMA 主导，fee 平滑升高 |
| 瞬间砸盘（5%/block） | ❌ 滞后 | ✅ 立即触发 | surge 主导，fee 瞬间拉到 3% |
| 市场恢复（价格回归） | ✅ EMA 跟上 | ✅ 自动衰减 | 两者都恢复到 base |

---

## 3. Hook Flags 与调用流

### 3.1 权限位

```solidity
function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
        beforeInitialize: true,      // 设置 pool 参数
        afterInitialize: false,
        beforeAddLiquidity: true,    // Anti-JIT 记录
        afterAddLiquidity: false,
        beforeRemoveLiquidity: true, // Anti-JIT 检查
        afterRemoveLiquidity: false,
        beforeSwap: true,            // 计算并覆盖动态 fee
        afterSwap: true,             // 更新 EMA + 检查 surge
        beforeDonate: false,
        afterDonate: false,
        beforeSwapReturnDelta: false,
        afterSwapReturnDelta: false,
        afterSwapReturnDelta: false,
        beforeAddLiquidityReturnDelta: false,
        afterAddLiquidityReturnDelta: false
    });
}
```

**注意**：`dynamicFee = true` 必须在 pool 初始化时设置（通过 `PoolKey` 的 `fee` 字段最高位）。

### 3.2 时序图

#### Pool 初始化

```
Deployer
   │  initializePool(key, sqrtPriceX96, hookData)
   ▼
PoolManager
   │  hook.beforeInitialize(msg.sender, key, sqrtPriceX96)
   ▼
RingLPHook
   ├─ 解析 hookData（baseFee, alphaShort, alphaLong, surgeParams）
   ├─ 初始化 poolStates[id]:
   │     emaShort = sqrtPriceX96        // 短周期 EMA 起点
   │     emaLong = sqrtPriceX96         // 长周期 EMA 起点
   │     alphaShort = alphaShort        // 如 0.1 (1e17)
   │     alphaLong = alphaLong          // 如 0.01 (1e16)
   │     baseFee = baseFee
   │     surgeActive = false
   ├─ 设置 dynamicFee = true（通过 updateDynamicLPFee）
   └─ return selector
```

#### Swap 流程

```
Trader
   │  swap(key, params)
   ▼
PoolManager
   │  hook.beforeSwap(sender, key, params)
   ▼
RingLPHook.beforeSwap
   ├─ 读 currentSqrtPriceX96（从 slot0）
   ├─ 读 poolStates[id]
   ├─ 计算 deviation
   ├─ 计算指数惩罚 fee
   ├─ 叠加 surgeFee（若 active）
   ├─ 叠加 directional premium
   ├─ clamp 到 [MIN, MAX]
   ├─ updateDynamicLPFee(newFee)  ← 覆盖 pool 的 LP fee
   ├─ 记录 lastSwapBlock[sender]
   └─ return (selector, 0, 0)
   │
   ▼
PoolManager 执行 swap（使用新 fee）
   │
   │  hook.afterSwap(sender, key, params, delta, hookData)
   ▼
RingLPHook.afterSwap
   ├─ _updateEMA(id, newSqrtPriceX96)
   ├─ _checkSurge(id, newSqrtPriceX96)
   ├─ _updateNetFlow(id, swapDirection, amount)
   └─ return (selector, 0)
```

#### Add Liquidity

```
LP
   │  addLiquidity(key, params)
   ▼
PoolManager
   │  hook.beforeAddLiquidity(sender, key, params)
   ▼
RingLPHook
   ├─ 记录 depositBlock[sender][id] = block.number
   └─ return selector
```

#### Remove Liquidity

```
LP
   │  removeLiquidity(key, params)
   ▼
PoolManager
   │  hook.beforeRemoveLiquidity(sender, key, params)
   ▼
RingLPHook
   ├─ blocksHeld = block.number - depositBlock[sender][id]
   ├─ if (blocksHeld < 300) {
   │      // 不阻止撤出，但标记为 JIT
   │      emit JITWithdrawal(sender, id, blocksHeld);
   │      // 高 fee 已经在 swap 时收取，这里只做记录
   │  }
   └─ return selector
```

---

## 4. 模块化设计：未来可扩展

RingLPHook 的三层设计允许未来独立替换/升级：

```
RingLPHook.sol
├── imports:
│   ├── AntiMEVLayer.sol      // Layer 1: JIT + repeat + directional + max sell
│   ├── DynamicFeeLayer.sol   // Layer 2: EMA + 指数惩罚
│   └── SurgeLayer.sol        // Layer 3: 熔断 + 衰减
│
├── 未来可选升级：
│   ├── MEVRebateLayer.sol    // 把部分 fee 回扣给被 sandwich 的 trader
│   ├── LotteryLayer.sol      // 随机抽一笔 swap 的 fee 免单（吸引流量）
│   └── StakingLayer.sol      // LP 可以把 fee 收益复投（自动复利）
```

每个 layer 通过接口交互，不影响其他层：

```solidity
interface IDynamicFeeLayer {
    function calculateFee(PoolId id, uint256 currentPrice, bool isBuy) 
        external view returns (uint24 fee);
}

interface IAntiMEVLayer {
    function validateSwap(address trader, PoolId id, uint256 amount) 
        external view returns (bool allowed, uint24 penaltyMultiplier);
}
```

---

## 5. Gas 分析：全量拆解

### 5.1 三层算法叠加后的 Gas 拆分

**`beforeSwap` 完整路径**（所有三层算法全部执行）：

| 步骤 | 算法 | Gas | 说明 |
|---|---|---|---|
| 1 | Repeat-Swap Penalty | ~2,200 | 读 `lastSwapBlock[trader]`（cold: ~2,100 + 比较 ~100） |
| 2 | Max Sell Limit | ~100 | 读 amount + 与 pool liquidity 比较（pool 状态已由 v4 提供） |
| 3 | Dual EMA 读 | ~4,200 | 读 `emaShort` + `emaLong`（各 cold ~2,100） |
| 4 | Dual EMA 偏离度计算 | ~1,500 | 2 次 abs + 除法 + max |
| 5 | 指数惩罚 | ~2,000-4,000 | `exp` 近似或查表；查表 ~2,000，实时 expWad ~4,000 |
| 6 | Surge 读 + 衰减 | ~2,500 | 读 `surgeActive` + `lastSurgeTimestamp`（packed ~2,100）+ 衰减计算 ~400 |
| 7 | Directional Fee | ~100 | 读 `netFlow`（已在 PoolState 中，若和 surge 同 slot 则已读） |
| 8 | 分级 MAX_FEE | ~200 | 2 次 if 比较 |
| 9 | updateDynamicLPFee | ~3,000 | v4 内部开销 |
| | **beforeSwap 总计** | **~15,800-17,800** | 热路径（重复用户）~3,000-5,000 |

**`afterSwap` 完整路径**：

| 步骤 | 算法 | Gas | 说明 |
|---|---|---|---|
| 1 | 更新 emaShort | ~5,000 | SSTORE（值一定变） |
| 2 | 更新 emaLong | ~5,000 | SSTORE（值一定变） |
| 3 | 检查 surge + 写 | ~5,000-8,000 | 读 deviation + 比较 + 可能写 surgeActive |
| 4 | 更新 netFlow | ~5,000 | SSTORE |
| | **afterSwap 总计** | **~20,000-23,000** | |

### 5.2 端到端对比

| 场景 | 总 Gas | 对比 v4 标准 | 说明 |
|---|---|---|---|
| v4 标准 swap | ~50,000 | 基准 | 无 hook |
| **RingLPHook 冷路径**（首次交互） | **~72,000-78,000** | **+44-56%** | 所有 storage cold read |
| **RingLPHook 热路径**（重复用户） | **~55,000-60,000** | **+10-20%** | storage warm，大部分读已 cache |
| EMADynamicFeeHook | ~60,000-65,000 | +20-30% | 单 EMA + anti-JIT，无 surge/directional |
| BVCC Dynamic Fee Hook | ~80,000-100,000 | +60-100% | 四维复合（gas/volatility/volume/24h） |

### 5.3 诚实的结论：确实高，但可控

**为什么高**：
- 6 个 storage read（beforeSwap）+ 4 个 storage write（afterSwap）= ~15,000-25,000 gas 纯 storage 开销
- 指数计算和偏离度计算另加 ~5,000 gas
- **这三层算法做齐了，冷路径不可能低于 70,000 gas**

**为什么可控**：
- 热路径（同一用户反复交易）storage 变 warm，gas 降到 ~55,000-60,000，只比标准 swap 贵 10-20%
- 仍低于 BVCC（80,000-100,000），且功能更聚焦
- 对大额 swap 而言，多出的 5,000-15,000 gas 远小于节省的 MEV 损失

### 5.4 Phase 1 裁剪方案（如果实测 gas 超预期）

如果 Foundry 实测冷路径 > 80,000 gas，按优先级裁剪：

| 优先级 | 算法 | 若裁剪节省 gas | 影响 |
|---|---|---|---|
| **必须保留** | Dual EMA + 分级 MAX_FEE | — | 核心差异化 |
| **必须保留** | Surge | ~2,500 | 闪电贷保护 |
| **必须保留** | Anti-JIT | ~5,000（仅 add/remove） | 基础保护 |
| **可裁剪 1** | Repeat-Swap Penalty | ~2,200 | 三明治攻击靠高 fee 间接防御 |
| **可裁剪 2** | Directional Fee | ~100-2,100 | 单边砸盘靠 surge 间接防御 |
| **可裁剪 3** | Max Sell Limit | ~100 |  whale 拆单本是好事（每笔都付 fee） |

**MVP 底线**：Dual EMA + 分级 MAX_FEE + Surge + Anti-JIT = 冷路径 ~65,000-70,000 gas，仍可接受。

### 5.5 优化空间

| 优化 | 预计节省 | 复杂度 |
|---|---|---|
| EMA 用 `uint160` 存 sqrtPriceX96 | ~500 gas | 低 |
| alphaShort/Long 做成 immutable（不读 storage） | ~4,200 gas（冷路径） | 低 |
| 指数用查表替代实时计算 | ~2,000 gas | 中 |
| PoolState 字段打包到更少 slot | ~2,000-4,000 gas | 中 |
| Surge + netFlow 同 slot 打包 | ~2,000 gas | 低 |

**乐观估计**：全部优化后，冷路径可降到 **~60,000-65,000 gas**。

---

*下一篇：[05-DESIGN_DECISIONS.md](05-DESIGN_DECISIONS.md) — 核心决策记录：为什么做 / 为什么不做*
