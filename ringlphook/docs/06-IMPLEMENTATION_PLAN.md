# RingLPHook Phase 1 MVP 实施计划

## 1. 范围定义

Phase 1 目标：**可部署、可验证、LP 敢存钱的动态 fee hook**

### 1.1 包含（In Scope）

| 模块 | 功能 | 优先级 |
|---|---|---|
| **Core Dynamic Fee** | EMA + 指数惩罚 + clamp | P0 |
| **Surge Protection** | 价格突变检测 + 指数衰减 | P0 |
| **Anti-JIT** | 300-block cooldown | P0 |
| **Repeat-Swap Penalty** | 同 block / 相邻 block 惩罚 | P1 |
| **Directional Fee** | 基于 netFlow 的动态 buy/sell 差异化 | P1 |
| **Max Sell Limit** | 单笔卖出量上限 | P2 |
| **Events & Monitoring** | 所有关键操作 emit event，方便 Dune 分析 | P1 |

### 1.2 不包含（Out of Scope）

| 功能 | 推迟原因 |
|---|---|
| Protocol fee 抽成 | Phase 1 100% 给 LP，最大化吸引力 |
| am-AMM 拍卖 | 冷启动风险，需观察 pool 活跃度后再评估 |
| MEV Rebate（给被 sandwich 的 trader 退款） | 需要复杂的事后分析，Phase 2 |
| Auto-compounding（LP 收益自动复投） | 需额外合约，Phase 2 |
| Multi-chain 部署 | 先 Ethereum 主网验证，再扩展 |
| 前端界面 | 依赖 Universal Router / Uniswap Frontend 即可交互 |

---

## 2. 技术栈

| 组件 | 选择 | 原因 |
|---|---|---|
| **Solidity 版本** | ^0.8.26 | v4 标准版本，支持 transient storage |
| **Framework** | Foundry | 测试、部署、验证一体化 |
| **v4 依赖** | `@uniswap/v4-core` + `@uniswap/v4-periphery` | 官方标准 |
| **Math 库** | Solady `expWad` | 已审计，gas 优化 |
| **状态管理** | 原生 mapping + struct | 无额外依赖，降低攻击面 |

---

## 3. 文件结构

```
ringlphook/
├── src/
│   ├── RingLPHook.sol              # 主合约：Hook 入口
│   ├── layers/
│   │   ├── AntiMEVLayer.sol        # Layer 1: JIT + repeat + directional
│   │   ├── DynamicFeeLayer.sol     # Layer 2: EMA + 指数惩罚
│   │   └── SurgeLayer.sol          # Layer 3: 熔断 + 衰减
│   ├── libraries/
│   │   ├── EMAHelper.sol           # EMA 计算辅助
│   │   ├── FeeMath.sol             # 指数惩罚 + clamp
│   │   └── SurgeMath.sol           # 指数衰减计算
│   └── types/
│       └── RingLPHookTypes.sol     # PoolState 等结构定义
├── test/
│   ├── RingLPHook.t.sol            # 主测试套件
│   ├── layers/
│   │   ├── AntiMEVLayer.t.sol
│   │   ├── DynamicFeeLayer.t.sol
│   │   └── SurgeLayer.t.sol
│   ├── invariant/
│   │   └── FeeInvariant.t.sol      # 不变量测试：fee 始终在 [MIN, MAX]
│   └── integration/
│       └── SwapScenario.t.sol      # 场景测试：闪电贷攻击、慢偏离恢复等
├── script/
│   ├── Deploy.s.sol                # 部署脚本
│   └── Verify.s.sol                # 验证脚本
├── docs/                           # 设计文档（已完成）
└── foundry.toml
```

---

## 4. 开发排期（估计）

| 阶段 | 内容 | 工期 | 产出 |
|---|---|---|---|
| **W1: 基础设施** | Foundry 配置、v4 依赖导入、CI 设置 | 2-3 天 | 可编译空合约 |
| **W1-W2: Layer 2 (核心)** | DynamicFeeLayer + EMAHelper + FeeMath | 4-5 天 | EMA 更新 + fee 计算通过单元测试 |
| **W2-W3: Layer 3** | SurgeLayer + 熔断/衰减逻辑 | 3-4 天 | surge 触发 + 衰减曲线通过测试 |
| **W3: Layer 1** | AntiMEVLayer + cooldown + repeat penalty | 3-4 天 | JIT 检测 + repeat 惩罚通过测试 |
| **W4: 集成** | RingLPHook.sol 组装 + hook flags 配置 | 3-4 天 | 完整 swap flow 通过集成测试 |
| **W4-W5: 场景测试** | 闪电贷、三明治、慢偏离、 surge 恢复 | 4-5 天 | 所有场景测试 green |
| **W5: 优化 & Gas** | Storage packing、公式优化、gas snapshot | 2-3 天 | Gas 报告 + 优化后 snapshot |
| **W6: 审计准备** | 文档、注释、形式化规范 | 3-4 天 | 审计就绪包 |

**总计：约 6 周（1 人全职）**

---

## 5. 关键测试场景

### 5.1 单元测试（每层独立）

#### DynamicFeeLayer

```solidity
function test_EMAUpdate() public {
    // 初始 EMA = 1000
    // 新价格 = 1100 (偏离 10%)
    // α = 0.1
    // 期望 EMA = 1000*0.9 + 1100*0.1 = 1010
}

function test_FeeAtZeroDeviation() public {
    // deviation = 0
    // fee 应该 = baseFee
}

function test_FeeExponentialGrowth() public {
    // deviation = 1%, 2%, 5%, 10%
    // 验证 fee 是指数增长，不是线性
}

function test_FeeClamp() public {
    // deviation = 50%
    // 即使指数计算 > MAX_FEE，实际返回 = MAX_FEE
}
```

#### SurgeLayer

```solidity
function test_SurgeTrigger() public {
    // 单 block 价格变化 > SURGE_THRESHOLD
    // 期望 surgeActive = true, lastSurgeTimestamp = block.timestamp
}

function test_SurgeDecay() public {
    // 触发 surge 后等待 halfLife
    // 期望 surgeFee = maxSurgeFee / 2
}

function test_SurgeAutoReset() public {
    // 触发 surge 后等待 > autostartThreshold
    // 期望 surgeActive = false
}
```

#### AntiMEVLayer

```solidity
function test_JITDetected() public {
    // block N: addLiquidity
    // block N+100 (< 300): removeLiquidity
    // 期望 emit JITWithdrawal
}

function test_JITNotDetected() public {
    // block N: addLiquidity
    // block N+400 (> 300): removeLiquidity
    // 期望正常撤出，无事件
}

function test_RepeatSwapPenalty() public {
    // 同一 block 内两次 swap
    // 第二次 fee 应该 > 第一次
}
```

### 5.2 集成测试（端到端）

#### 场景 1：正常交易

```
初始：EMA = 1000，current = 1000，fee = 0.05%
Trader swap：买入 1 ETH
期望：fee = 0.05%，EMA 轻微更新
```

#### 场景 2：慢偏离（套利者尝试）

```
Block 1: EMA = 1000, current = 1000
Block 2: current = 1010 (+1%), EMA = 1001
Block 3: current = 1020 (+1%), EMA = 1003
...（套利者持续抬价）
Block 50: current = 1500 (+50%), EMA ≈ 1200
期望：fee 从 0.05% 逐渐升到 ~1.5%，套利利润空间被压缩
```

#### 场景 2b：慢速均匀下跌（1 小时跌 2%，双 EMA 核心测试）

```
Block 0:   current = 1000, emaShort = 1000, emaLong = 1000
Block 50:  current = 990,  emaShort = 999,  emaLong = 1000  (devLong = 1.0%)
Block 100: current = 980,  emaShort = 997,  emaLong = 999   (devLong = 1.9%)
Block 200: current = 960,  emaShort = 990,  emaLong = 996   (devLong = 3.6%)
Block 300: current = 940,  emaShort = 980,  emaLong = 990   (devLong = 5.0%)

期望：
  - 单 EMA：最终 fee ≈ 0.37%（deviation = 2.0%）
  - 双 EMA：最终 fee ≈ 1.80%（deviation = 5.0%，取 emaLong 滞后）
  - 验证：devLong > devShort 在整个过程中成立
  - 验证：LP fee 收入足以部分补偿 IL
```

#### 场景 3：闪电贷攻击

```
Block N: EMA = 1000, current = 1000
Block N+1: 闪电贷砸盘，current = 900 (-10%)
期望：
  - surge 触发（单 block 变化 > 1%）
  - fee 瞬间 = 3%（MAX_FEE）
  - 套利者利润 = 10% - 3% - 闪电贷成本 ≈ 无利可图
Block N+2: current = 905（恢复一点）
期望：fee 开始衰减，但 still high（~2%）
```

#### 场景 4：三明治攻击

```
Block N: User 提交 buy ETH
MEV Bot: front-run (buy ETH)
         → 被 repeat-swap penalty 高 fee
         → 用户 swap（正常 fee）
         → back-run (sell ETH)
         → 被 repeat-swap penalty 高 fee
期望：bot 的 front-run + back-run 都被 penalty，总利润 < 成本
```

### 5.3 不变量测试（Invariant Tests）

```solidity
function invariant_feeAlwaysInRange() public {
    // 对任意 pool，任意时间：MIN_FEE <= fee <= MAX_FEE
}

function invariant_emaNeverZero() public {
    // EMA 一旦初始化，永远不会归零（除非 pool 被攻击）
}

function invariant_emaLongLagsEmaShort() public {
    // 在匀速单向趋势中，emaLong 应该比 emaShort 更远离当前价格
    // （即长周期 EMA 的滞后性）
}

function invariant_deviationUsesMaxOfBothEma() public {
    // deviation 应该 >= devShort 且 >= devLong
}

function invariant_surgeFeeAlwaysDecaying() public {
    // 若 surgeActive，每次检查 fee 应该 <= 上一次
}

function invariant_slowDeclineDetected() public {
    // 模拟 300 blocks 匀速跌 2%，验证 deviation >= 4%
    // （即 emaLong 的滞后被正确捕捉）
}
```

---

## 6. 部署计划

### 6.1 测试网（Sepolia）

| 步骤 | 内容 |
|---|---|
| 1 | 部署 RingLPHook 到 Sepolia |
| 2 | 创建测试 pool（如 WETH/USDC） |
| 3 | 用脚本模拟：正常 swap、闪电贷、JIT、三明治 |
| 4 | 验证 fee 行为是否符合预期 |
| 5 | 邀请外部 LP 存入测试资金 |

### 6.2 主网（Ethereum）

| 步骤 | 内容 |
|---|---|
| 1 | 代码审计（至少 1 家，建议 2 家） |
| 2 | 部署前 bug bounty（Immunefi，1 周） |
| 3 | 主网部署 |
| 4 | Ring Protocol 作为首批 LP 存入 |
| 5 | 逐步开放给外部 LP |
| 6 | Dune 看板监控：TVL、fee 收入、swap 量、surge 频率 |

### 6.3 部署参数建议

| 参数 | 初始值 | 可调性 |
|---|---|---|
| `baseFee` | 500 (0.05%) | Pool 初始化时设定，不同 pool 可不同 |
| `alphaShort` | 0.1 (1e17) | **Pool 初始化时设定，immutable** |
| `alphaLong` | 0.01 (1e16) | **Pool 初始化时设定，immutable** |
| `MIN_FEE` | 100 (0.01%) | Immutable |
| `MAX_FEE` | 30000 (3%) | Immutable |
| `SURGE_THRESHOLD` | 100 (1%) | Timelock 可调整 |
| `MAX_SURGE_FEE` | 30000 (3%) | Immutable |
| `SURGE_HALF_LIFE` | 300s | Timelock 可调整 |
| `SURGE_AUTOSTART_THRESHOLD` | 3600s (1hr) | Timelock 可调整 |
| `JIT_COOLDOWN` | 300 blocks | Immutable |
| `REPEAT_PENALTY_BASE` | 2x | Immutable |
| `DIRECTIONAL_PREMIUM` | 1.5x | Timelock 可调整 |
| `MAX_SELL_RATIO` | 100 (1% of pool) | Timelock 可调整 |

**双 EMA 参数选择指南**：

| Pair 类型 | alphaShort | alphaLong | 理由 |
|---|---|---|---|
| 高波动山寨币 | 0.05 | 0.005 | 波动大，EMA 需更迟钝 |
| 中波动主流币 | 0.1 | 0.01 | 平衡默认值 |
| 低波动稳定币 | 0.2 | 0.02 | 波动小，EMA 可以更敏感 |

---

## 7. 风险与缓解

| 风险 | 可能性 | 影响 | 缓解 |
|---|---|---|---|
| 公式参数选错（α 太高/太低） | 中 | 高 | 测试网充分测试；timelock 调整 surge 参数；α immutable 但可通过新 pool 迭代 |
| 闪电贷绕过 surge（多 block 慢砸） | 低 | 高 | EMA 会跟上；多 block 攻击成本指数级上升 |
| Gas 过高导致交易者流失 | 中 | 中 | 持续优化 storage 布局；与 v4 标准 pool 对比 gas snapshot |
| LP 不信任新机制（不敢存入） | 中 | 高 | Ring Protocol 自己先存入大额；完全 immutable 核心；开源 + 审计 |
| EMA 被长期操纵 | 低 | 高 | 需要持续多个 block 维持错误价格，成本 > 收益；surge 增加操纵成本 |
| 合约 bug 导致 fee 异常 | 低 | 极高 | 全面测试 + 审计 + bug bounty；clamp 做最后防线 |

---

## 8. 成功指标

| 指标 | Phase 1 目标（3 个月） |
|---|---|
| TVL | > $1M（Ring Protocol + 外部 LP） |
| 日均 Swap 量 | > $100K |
| 平均 Fee | 0.10% - 0.30%（健康区间） |
| Surge 频率 | < 1% 的 swaps（极端情况才触发） |
| LP APY | > v3/v4 同 pair 标准池（证明"保护有价值"） |
| Gas Overhead | < 50% vs vanilla v4 swap |

---

## 9. Phase 2 展望（不承诺，仅规划）

| 功能 | 前提条件 |
|---|---|
| Protocol fee（10% of LP fee） | TVL > $10M，且 LP 仍然满意 APY |
| am-AMM（简化版） | 单 pool 30d 交易量 > $10M，证明有活跃 swap 流可拍卖 |
| Auto-compounding | LP 需求强烈 |
| Multi-chain（Arbitrum/Base） | 主网验证成功 |
| MEV Rebate | 有明确的三明治受害者案例 + 技术方案成熟 |

---

*文档完。下一篇：[07-EXTREME_SCENARIO_ANALYSIS.md](07-EXTREME_SCENARIO_ANALYSIS.md) — 大跌场景下的 LP 保护与 IL 分析。*

*下一步：切 Code mode 开始写合约代码，或根据反馈调整设计。*
