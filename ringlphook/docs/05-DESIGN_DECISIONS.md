# 核心设计决策记录

本文档记录 RingLPHook 的所有关键决策，包括**为什么做**、**为什么不做**、**为什么这样做而不是那样做**。

---

## 1. 目标与定位决策

### 1.1 为什么做新 Hook，而不是升级现有 9 个 Few Hook？

**选择：全新 RingLPHook，旧资金可迁移，但不做 in-place 升级。**

| 方案 | 分析 | 结论 |
|---|---|---|
| 升级现有 Few Hook | Few Hook 是 immutable 的 wrap 逻辑，叠加 dynamic fee 需要改核心路径，可能破坏现有集成 | ❌ |
| 做新 Hook + 资金迁移 | 新 Hook 独立演进，不影响现有业务；旧池子资金逐步迁到新池 | ✅ |
| 同时维护两套 | 新 Hook 面向通用 pair，Few Hook 继续服务 wrap 需求，长期并存 | ✅（最终状态） |

**关键考量**：
- 现有 Few Hook 的 `swapAccess = none` 和 `zero fee` 是设计意图，改它等于推翻重造
- 新 Hook 可以吸引**外部 LP**（不只是 Ring 团队自己），这是增长故事
- Uniswap V4 支持同一 pair 多个 pool（不同 hook），新 Hook 可以与旧 pool 共存竞争

---

### 1.2 为什么定位"通用 LP 保护"，而不是"Ring 专属"？

**选择：RingLPHook 是通用 hook，不只是服务 Ring 生态。**

| 方向 | 优势 | 劣势 |
|---|---|---|
| Ring 专属 | 深度集成 fewToken wrap | 天花板低，只服务 Ring 自己的 pair |
| **通用 LP 保护** | 任何 pair 都能用，外部 LP 会存入，TVL 增长空间大 | 需要保证通用性，不能做 Ring 特定假设 |

**决策依据**：
- Uniswap V4 的设计哲学就是"hook 即产品"，最好的 hook 是**通用的**
- Ring Protocol 作为 LP 可以在自己的 hook 里提供流动性，享受更好的保护 + 更高的 fee
- 外部 LP 的流入 = Ring Protocol 的**隐性品牌收益**（"Ring 做的 hook 好用"）

---

## 2. 算法决策

### 2.1 为什么 EMA + 指数惩罚，而不是纯 EMA 阶梯或纯 StableStableHook？

详见 [03-ALGORITHM_SELECTION.md](03-ALGORITHM_SELECTION.md)，此处总结关键决策点。

**选择：EMA 作为"自参考基准" + StableStableHook 的指数惩罚公式 + Clamp 上限。**

| 方案 | 为什么不做 | 为什么选当前方案 |
|---|---|---|
| **纯 StableStableHook** | 需要外部锚定价格，任意 pair 不适用 | EMA 是"自参考"的，任意 pair 自动适配 |
| **纯 EMADynamicFeeHook** | 30-step 阶梯有"边界可预测性"问题，套利者可卡点；缺乏 surge 熔断 | 指数公式连续平滑，无边界可预测性；叠加 surge 防闪电贷 |
| **BVCC 四维复合** | gas 高（~80k-100k），过度设计，有中心化风险 | 单公式 gas 低（~15k），immutable，LP 敢存大钱 |

**数学层面的为什么**：

指数函数 `exp(x)` 是**凸函数**，意味着：
- 小偏离时惩罚温和（保护正常交易者）
- 大偏离时惩罚急剧上升（对套利者致命）
- 没有"阶梯边界"，套利者无法预测"差 0.01% 就跳到下一档"的精确操作点

---

### 2.2 为什么 surge 用"指数衰减"而不是"线性衰减"或"立即归零"？

**选择：指数衰减（halfLife = 300-600s）。**

| 方案 | 问题 |
|---|---|
| **立即归零** | surge 触发后下一秒就回到 base fee，套利者可以等 1 个 block 再攻击 |
| **线性衰减** | 衰减速度恒定，数学上不如指数衰减"前期快、后期慢"符合市场恢复规律 |
| **指数衰减** | 触发后前几分钟快速下降（阻止 immediate 二次攻击），后期缓慢恢复（给市场充分时间稳定） |

**类比**：
- 类似放射性衰变："半衰期"概念直观，且可数学证明是最优恢复曲线
- BunniHook 也选择指数衰减，不是巧合

---

### 2.4 为什么用双 EMA 而不是单 EMA？

**选择：双 EMA（短周期 + 长周期，取 max 偏离度）。**

| 问题 | 单 EMA 的问题 | 双 EMA 的解决 |
|---|---|---|
| **慢速均匀下跌** | EMA 紧跟价格，deviation ≈ 0，fee 始终很低 | 长周期 EMA 滞后大，devLong 很大，fee 显著升高 |
| **瞬间砸盘** | EMA 滞后，deviation 大，fee 高 | 短周期 EMA 也滞后但 less，+ surge 熔断，足够 |
| **正常波动** | 单 EMA 可能过于敏感或迟钝 | 短周期 EMA 反应日常波动，长周期 EMA 忽略噪音 |

**具体场景对比**（1 小时均匀跌 2%）：

| 指标 | 单 EMA (α=0.1) | 双 EMA (短 0.1 + 长 0.01) |
|---|---|---|
| 最终 deviation | 2.0% | 5.0%（emaLong 滞后） |
| Fee | ~0.37% | ~1.80% |
| LP 补偿 | 弱 | **强（5 倍 fee 收入）** |

**代价**：
- 多 1 个 storage slot（emaLong）
- `afterSwap` 多 1 次 SSTORE（~5,000 gas）
- `beforeSwap` 多 1 次偏离计算（~2,000 gas）

**结论**：额外 ~7,000 gas 换取对"慢刀子割肉"的 5 倍保护提升，**值得**。

---

### 2.5 为什么 α 可配置（per-pool），而不是全局固定？

**选择：`alphaShort` + `alphaLong` pool 初始化时设定，immutable。**

| Pair 类型 | alphaShort | alphaLong | 理由 |
|---|---|---|---|
| 高波动山寨币 | 0.05 | 0.005 | 波动大，需要更迟钝的 EMA 才能分辨"真趋势"vs"噪音" |
| 中波动主流币 | 0.1 | 0.01 | 平衡，默认值 |
| 低波动稳定币 | 0.2 | 0.02 | 波动小，EMA 可以更敏感 |

**为什么 immutable**：
- 防止治理攻击（恶意改 α 让 fee 体系失效或定向收割）
- LP 存入前可以审计确认参数，增加信任
- 若参数不理想，可部署新 pool 迁移，旧 pool 不受影响

**为什么不在运行时调整**：
- EMA 的 α 一旦改变，历史 EMA 值就"不对了"（α 变了权重结构就变了）
- 运行时改 α 需要重置 EMA = 攻击窗口

---

### 2.3 为什么 clamp 到 [MIN_FEE, MAX_FEE]，而不是无上限？

**选择：MIN_FEE = 0.01% (1 bps)。MAX_FEE 不再固定为 3%，而是分级动态上限。**

| 问题 | 回答 |
|---|---|
| 为什么不无上限？ | 极端情况下 fee 可能涨到 100%，池子"被自己杀死"，没人愿意交易 |
| 为什么 MAX_FEE 分级？ | 固定 3% 在偏离 20% 时经济学上过高（交易量归零）；偏离 5%+ 时 1% 已足够阻止套利 |
| 为什么 MIN = 0.01%？ | 低于此值 gas 成本占比过高，且 v4 最低支持 1 bps |

**分级 MAX_FEE**（详见 [03-ALGORITHM_SELECTION.md](03-ALGORITHM_SELECTION.md) 4.4）：
- 偏离 < 2%：MAX = 3.00%（正常波动，交易量不敏感）
- 偏离 2% ~ 5%：MAX = 1.50%（下跌区间，保留边际交易）
- 偏离 >= 5%：MAX = 1.00%（极端行情，阻止套利 > 赚 fee）

**动态范围**：
- 正常市场：0.05% - 0.30%
- 偏离市场：0.30% - 1.00%
- 极端/attack：1.00% - 3.00%（但分级后实际封顶 1.50%）

---

## 3. 机制决策

### 3.1 为什么用"经济惩罚"而不是"访问控制"（黑名单/KYC）？

**选择：纯经济手段（高 fee 劝退），不做 blacklist/allowlist。**

| 方案 | 为什么不做 | 为什么选经济手段 |
|---|---|---|
| **Blacklist**（CustomFeeMEVHook） | Owner 可以定向封锁地址 = 中心化风险；区块链精神是 permissionless | 高 fee 是"算法决定"，不是"owner 决定"，immutable |
| **KYC / Allowlist**（M0） | 违背"吸引外部 LP"目标；增加运营负担；合规成本高 | 完全开放，任何人可以 swap/add LP，fee 机制自动筛选 |
| **Predicate 签名** | 链下签名验证 = 外部依赖；签名方私钥泄露 = 全池卡死 | 纯 on-chain，无外部依赖 |

**关键洞察**：
- MEV 保护有两种哲学：
  - **排除型**："你是坏人，我不让你进"（Angstrom 的 Solver 拍卖、M0 的 KYC）
  - **经济型**："你可以进，但你得付足够多的 fee，让套利无利可图"
- RingLPHook 选择**经济型**，因为：
  1. 与 Uniswap 的 permissionless 精神一致
  2. 外部 LP 看到"没有 blacklist risk"更愿意存入
  3. 不需要运营团队维护名单/KYC 流程

---

### 3.2 为什么 Anti-JIT 是"300 block cooldown"而不是"禁止撤出"或"无保护"？

**选择：300 block 内撤出 = 高 fee（不禁止）。**

| 方案 | 问题 |
|---|---|
| **无保护** | JIT 套利者寄生在 LP 流动性上，正常 LP 收益被稀释 |
| **禁止撤出（< 300 blocks）** | 过于严格， legitimate LP 可能急需资金；且引入"禁止"能力 = 中心化风险 |
| **300 block + 高 fee** | JIT 套利者无利可图（fee > 套利空间），正常 LP 可以等 1 小时或付高 fee 应急撤出 |

**为什么是 300 blocks？**
- 以太坊 12s/block ≈ 300 × 12 = 3600s = 1 小时
- 足够覆盖"看到交易 → 执行 JIT 攻击"的整个时间窗口
- EMADynamicFeeHook 在主网用此参数已验证

---

### 3.3 为什么 Directional Fee 根据"历史净流向"动态调节，而不是固定 buy/sell 差额？

**选择：动态 directional fee，根据过去 N 个 block 的 netFlow 自动调节。**

| 方案 | 问题 |
|---|---|
| **固定 buyFee / sellFee** | 市场结构变化后（如从牛市变熊市），固定差额可能反向激励 |
| **动态 netFlow 调节** | 自动适应市场方向：净卖出多 → sell fee 更高 → 抑制继续卖出 → 帮助价格回归 |

**机制**：
```solidity
if (netFlow < -THRESHOLD) {  // 净卖出过多
    sellFee = baseFee × PREMIUM;  // 卖更贵
    buyFee = baseFee × DISCOUNT;  // 买更便宜
} else if (netFlow > THRESHOLD) {  // 净买入过多
    buyFee = baseFee × PREMIUM;
    sellFee = baseFee × DISCOUNT;
}
```

**为什么有效**：
- 类似"动态关税"：当某方向压力过大时，自动增加该方向的"摩擦成本"
- 不需要外部输入，纯 on-chain 计算

---

### 3.4 为什么不做 am-AMM（Bunni 的拍卖机制）？

**选择：不做 am-AMM。**

| 论点 | 分析 |
|---|---|
| "am-AMM 可以把 LVR 内部化，LP 收益更高" | 理论上对，但需要：1) 活跃的竞价市场；2) LP 理解并把头寸 NFT 抵押出去 |
| "Bunni 做了，说明可行" | Bunni 是专业 CL 协议，有完整生态（BunniToken、Hub、FloodPlain）；Ring 团队资源不同 |
| "对 fewToken 场景" | fewToken 交易量低，am-AMM 的"未来 swap 流"拍卖可能**冷启动失败**——没人愿意为一个低流量池子持续出价 |
| "押金被 burn 的风险" | 出价者判断错误 = 永久损失，这种风险会让 LP/出价者望而却步 |

**替代方案**：
- 用 surge fee + 指数惩罚替代 am-AMM 的"LVR recapture"
- 虽然理论上不如 am-AMM 最优，但实现简单、无运营负担、对 LP 透明

---

### 3.5 为什么不做 Angstrom？

**选择：完全不采用 Angstrom 的任何组件。**

| 维度 | Angstrom | RingLPHook |
|---|---|---|
| **基础设施** | 需要自建 Solver 网络（类似 CowSwap） | 纯 on-chain |
| **集成成本** | `requiresCustomSwapData = true`，普通 Router 无法调用 | `swapAccess = none`，Universal Router 直接支持 |
| **运营团队** | 需要持续运营 Solver 竞争、拍卖、清算 | 部署后自动运行，无需运营 |
| **审计范围** | 不只是 hook，还要审计整个 Solver 网络 + EIP-712 验证 | 只需审计 hook 合约本身 |
| **LP 收益提升** | 理论上最高（完全消除 MEV） | 次优（经济抑制），但"次优 × 可行" > "最优 × 不可行" |

**关键认知**：
- Angstrom 的 $268M 交易量不是"hook 的功劳"，是"整个 Solver 生态的功劳"
- RingLPHook 的目标是"做最好的**可独立运行**的 LP hook"，不是"做最小的 DEX 协议"

---

## 4. 经济模型决策

### 4.1 为什么 Phase 1 不收 Protocol Fee？

**选择：100% LP fee 给 LP，0% Hook protocol fee。**

| 方案 | 为什么不做 |
|---|---|
| **Bunni 模式：LP fee + hook fee + referral** | 降低 LP 实际 APY，削弱"吸引外部 LP"的核心竞争力 |
| **BVCC 模式：抽小部分 protocol fee** | 初期 TVL 小的时候，protocol fee 收入微不足道，但 LP 感知到的"抽成"是实实在在的心理障碍 |
| **100% 给 LP** | 最大化 LP APY，吸引外部资金；Ring Protocol 作为早期 LP 享受最大收益；未来可通过新 pool 逐步引入 protocol fee |

**未来选项**：
- Phase 2 可考虑 `afterSwapReturnsDelta` 加一层 optional protocol fee（如 10% of LP fee）
- 通过新 pool 引入，不影响旧 pool 的"immutable 承诺"

---

### 4.2 为什么 LP 收益比"消除 MEV"更重要？

**选择：优化 LP 收益，而不是追求 100% MEV 消除。**

| 哲学 | 代表 | RingLPHook 立场 |
|---|---|---|
| **MEV 消除主义** | Angstrom、CowSwap | "MEV 是邪恶的，必须完全消除" |
| **MEV 内部化** | Bunni am-AMM | "MEV 不可避免，但可以通过拍卖让 LP 分到一杯羹" |
| **MEV 经济抑制** | RingLPHook | "MEV 可以被高 fee 抑制到'无利可图'的程度，LP 收益自然提升" |

**数学直觉**：
- 假设套利者利润 = 价格差 × 交易量 - fee
- Angstrom：把套利者完全排除（需要复杂基础设施）
- Bunni：让套利者进来，但收拍卖费（需要活跃竞价市场）
- RingLPHook：让套利者进来，但 fee 高到利润 ≤ 0（纯 on-chain 公式）

**为什么经济抑制对 Ring 最优**：
1. 不需要任何外部基础设施
2. 不需要运营团队
3. LP 收益 = fee 收入，fee 越高 LP 越开心（只要还有正常交易量）
4. 正常交易者只在市场混乱时付高 fee，平时 fee 很低

---

## 5. 技术决策

### 5.1 为什么 Immutable 核心公式，但 surge 参数可管理？

**选择：核心算法 immutable，surge 阈值/halfLife 允许 minimal governance。**

| 组件 | 可变性 | 原因 |
|---|---|---|
| EMA 公式 | **Immutable** | 数学上不需要改，改了反而破坏 LP 信任 |
| 指数惩罚公式 | **Immutable** | 同上 |
| baseFee | **Immutable** | pool 初始化时确定，不同 pool 可以有不同 baseFee |
| surgeThreshold | **可管理** | 市场结构变化可能需要调整（如从低波动市场到高波动市场） |
| surgeHalfLife | **可管理** | 同上 |
| maxSurgeFee | **Immutable** | 3% 上限是 LP 的"安全承诺" |

**治理最小化**：
- 只有 2 个参数可调整（threshold, halfLife）
- 调整通过时间锁（timelock，如 3 天延迟）
- 任何人都可以提议，但需要高门槛通过（防止恶意调整）

---

### 5.2 为什么不用外部预言机？

**选择：纯 on-chain 数据（pool 自己的价格历史）。**

| 方案 | 为什么不做 |
|---|---|
| **Chainlink Price Feeds** | 增加外部依赖；预言机故障 = 池子瘫痪；额外成本（LINK 付费） |
| **Uniswap V3 TWAP** | 需要读另一个合约，gas 增加；且 V3 TWAP 本身也可被操纵 |
| **自参考 EMA** | 零外部依赖；pool 自己的价格历史 = 最难操纵的参考；gas 最低 |

**抗操纵性**：
- EMA 是历史平均，单次价格操纵影响有限（α = 0.1，当前价格只影响 10%）
- 要操纵 EMA 需要**持续**多个 block 维持错误价格 = 成本极高
- Surge 熔断进一步增加"快速操纵"的成本

---

## 6. 决策总表

| # | 决策 | 选择 | 关键理由 |
|---|---|---|---|
| 1 | 新 Hook vs 升级旧 Hook | 新 Hook | 旧 Hook immutable，新 Hook 面向未来 |
| 2 | 通用 vs Ring 专属 | 通用 | 吸引外部 LP，增长天花板高 |
| 3 | 核心算法 | EMA + 指数惩罚 | 任意 pair + 连续惩罚 + 无阶梯边界 |
| 3a | 双 EMA | 短周期 + 长周期取 max | 解决单 EMA 对"慢跌"的盲区 |
| 3b | α 可配置 | per-pool immutable | 不同 pair 波动特性不同，参数应差异化 |
| 4 | Surge 机制 | 指数衰减 | 最优恢复曲线，防二次攻击 |
| 5 | Fee 上限 | 分级 MAX_FEE（<2%→3%, 2-5%→1.5%, >=5%→1%） | 防止数学溢出 + 经济学上不过高 |
| 6 | MEV 保护哲学 | 经济抑制 | permissionless，无运营负担 |
| 7 | Anti-JIT | 300 block + 高 fee | 不禁止，只让 JIT 无利可图 |
| 8 | Directional fee | 动态 netFlow 调节 | 自动适应市场方向 |
| 9 | am-AMM | 不做 | 冷启动风险，运营负担 |
| 10 | Angstrom | 完全不做 | 基础设施成本 > LP 收益增量 |
| 11 | Protocol fee | Phase 1 不收 | 最大化 LP APY 吸引流动性 |
| 12 | Immutable | 核心公式 immutable | LP 信任 = 大资金敢存入 |
| 13 | 预言机 | 不用外部 | 零依赖，最低攻击面 |
| 14 | 权限位 | beforeSwap + afterSwap + beforeAddLiquidity | 最小必要集合 |

---

## 7. 已知缺陷与 Tradeoff（诚实披露）

### 7.1 Alpha Immutable = 参数选错无法补救

**问题**：`alphaShort` / `alphaLong` 部署后永不可改。如果市场波动特性变化（例如 ETH 从"中波动"变成"高波动"），原参数可能让 EMA 太慢或太快。

**为什么接受这个缺陷**：
- 运行时改 α 需要重置 EMA，制造攻击窗口
- 防止治理攻击（owner 改 α 让 fee 体系失效）

**缓解策略**：
- 多池竞争：同一 pair 部署 2-3 个不同 alpha 的 pool，让市场用脚投票
- 运营方（Ring Protocol）在前 2 周密切监控 TVL / volume / fee 数据，不理想的 pool 不再推广

### 7.2 持续单边下跌 = 僵尸池（无法自救）

**问题**：ETH $2500 → $2000，每 block 都在跌，EMA 永远跟不上，fee 卡在分级上限（如 1%），交易量归零。

**为什么不能解决**：
- 链上没有 cron job，"50 blocks 无交易检测"逻辑本身无法被触发（没人调用合约）
- 即使能检测，加速 EMA 收敛等于给套利者更低 fee 窗口
- AMM 没有"rebalance"操作，价格由储备比决定，不是外部报价

**Hook 的真实边界**：
- ✅ 下跌初期：有交易量时收高 fee，补偿 LP
- ✅ 阻止套利者"补刀"
- ❌ 不能在市场彻底放弃这个池子后"自救"

**LP 的出路**：300 blocks cooldown 后撤出，认栽。这是 AMM 的结构性风险，不是 Hook bug。

### 7.3 分级 MAX_FEE 降低极端行情下的 fee 收入

**Tradeoff**：
- 固定 MAX=3%：极端偏离时 LP 理论上可赚更多 fee（如果还有交易量的话）
- 分级 MAX（>=5%→1%）：牺牲了极端行情的理论 fee 上限，换取交易量不瞬间归零

**这个 tradeoff 是值得的**：
- 偏离 5%+ 时，3% fee 几乎不可能还有交易量（套利者都跑了）
- 1% fee 保留的"边际交易量" > 3% fee 的"零交易量"

---

*下一篇：[06-IMPLEMENTATION_PLAN.md](06-IMPLEMENTATION_PLAN.md) — Phase 1 MVP 实施计划与排期*
