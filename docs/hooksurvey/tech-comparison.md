# Hook 技术横向对比

> **数据基线**：
> - [defillama.com/protocols/hook-based-amm](https://defillama.com/protocols/hook-based-amm)（Hook-based AMM 分类，2026-06-04 抓取）
> - [`hook-survey-mainnet.md`](file:///Users/alexla/code/ringprotocol/hooklist/docs/hooksurvey/hook-survey-mainnet.md)（Ethereum Mainnet Dune 30d 调研，8125 条记录）
> - 已收录的 50+ hook README 详情
>
> **生成时间**：2026-06-04
> **目的**：把已识别的 hook 技术做横向归类，给 Ring Protocol 选型用

---

## 一、defillama 数据基线（Hook-based AMM 分类）

| 协议 | TVL | 7d DEX 交易量 | 7d Fees | 部署链 |
|---|---|---|---|---|
| **Uniswap V4** | $615.43m | $7.499b | $6.77m | 16 chains |
| **PancakeSwap Infinity** | $78.39m | $1.196b | $156K | 2 chains |
| Hydrex Omni | $1.94m | – | – | 1 chain |
| **Hybra V4** | $1.05m | $19.01m | $14K | Hyperliquid L1 |
| **Angstrom** | $980K | $76.48m | $28K | 1 chain |
| Alphix | $313K | $1.77m | $514 | 2 chains |

**全分类总盘子**：TVL $703m / 7d 交易量 $8.79b / 7d Fees $6.97m

> 注：Uniswap V4 单家占了 **90% 交易量**，但单个 hook 维度看（hook-survey-mainnet.md 口径），$1.89B 30d 量分散在 1000 个 hook 上。

---

## 二、Ethereum Mainnet hook 量级（hook-survey-mainnet.md 口径）

### 30d 交易量 Top 10

| 排名 | 项目名 | 30d 交易量 | Swap 数 | 池数 | 类别 |
|---|---|---|---|---|---|
| 1 | Sat1 Hook - Sato Style | $738.40M | 37,505 | 1 | Other（RFQ-style P2P） |
| 2 | **Angstrom** | $268.36M | 79,450 | 2 | Dynamic Fee（拍卖） |
| 3 | Unlabeled | $173.29M | 249 | 1 | Other |
| 4 | Kyber | $94.39M | 3,756 | 75 | Liquidity（聚合路由） |
| 5 | Sato Hook | $77.52M | 34,402 | 1 | Other（RFQ） |
| 6 | StableStableHook | $74.42M | 20,418 | 1 | Dynamic Fee（surge） |
| 7 | VirtualLBPStrategyBasic (Aztec CCA) | $54.98M | 28,380 | 1 | Access Controlled（LBP） |
| 8 | UpegHook | $39.80M | 41,569 | 9 | Liquidity（多池复用） |
| 9 | Unlabeled | $18.21M | 8,269 | 3 | Other |
| 10 | WETHHook | $18.09M | 15,860 | 1 | Liquidity（1:1 wrap） |

### hook 分类与数量

| 类别 | 数量 | 描述 |
|---|---|---|
| Dynamic Fee | 5 | 根据市场条件动态调整手续费 |
| Access Controlled | 2 | swap 受白名单/治理/时间锁约束 |
| Trading Hook | 2 | swap 前后执行自定义逻辑（LaunchHook / PAMHook） |
| Liquidity Hook | 14 | 流动性添加/移除时执行逻辑 |
| Initialization Hook | 2 | 池子初始化时执行逻辑（HookdRandom / LimitOrder） |
| Other | 975 | 未分类（含所有 unlabeled） |
| **合计** | **1000** | |

---

## 三、技术横向对比（核心表）

> **列 1：技术特色**（即 hook 解决什么问题 / 用什么手段）
> **列 2：代表的主要 Hook**

| # | 技术特色（列 1） | 代表的主要 Hook（列 2） | 量级 / 数据基线 |
|---|---|---|---|
| 1 | **应用专属拍卖 + MEV 内部化**（链下 Solver 网络 + EIP-712 签 + 链上校验） | **Angstrom**（Sorella） | $268M 30d / $76M 7d |
| 2 | **动态费率（surge fee）**（pool 价格偏离 → 自动抬 fee） | StableStableHook（Uniswap 官方）、BunniHook | $74M 30d |
| 3 | **CL 池 + 外部定价源 + 动态费率**（Hook 拉外部 `DynamicFeeManager`） | Aegis | $8.2K 30d（小众） |
| 4 | **集中度 LP + 动态费率 + ve(3,3) 排放**（HyperEVM 原生） | **Hybra V4** | $1.05m TVL / $19M 7d |
| 5 | **Lending-Vault-backed AMM + JIT 流动性**（LP 资产留在 Euler 借贷金库） | **EulerSwap** | $1.6M 30d 交易量 / $4.33B 累计 |
| 6 | **AMM 集中度 + 动态曲线参数 + Reconfigure**（不重部署改 pool 参数） | EulerSwap V2 | 同上 |
| 7 | **1:1 wrap 桥接**（ETH↔WETH、LST↔underlying via hook delta） | WETHHook（WETH/ETH）、WstETHHook、Ring Few 系列 | $18M 30d |
| 8 | **RFQ-style P2P 撮合**（链下询价 + 链上 settle，绕过集中度） | **Sat1 Hook** | $738M 30d（Ethereum 第一） |
| 9 | **LBP 启动治理门**（migration approval gating 启动期 swap） | VirtualLBPStrategyBasic（Aztec CCA） | $54.98M 30d |
| 10 | **Launchpad 税**（flat 2% buy / 1% sell） | LaunchHook（Tickr）、TokenWorks v4、TTTHook | $0.5–2.7M 30d |
| 11 | **衰减税**（99%→1% 随区块线性衰减） | TTTHook、TokenWorks v3/v4 | $2.7M 30d |
| 12 | **多池共享 hook**（9 pool × 41569 swap 共用 1 hook） | UpegHook（Uniswap 官方） | $39.8M 30d |
| 13 | **链上 KYC + ACL**（LP/Swapper allowlist + Predicate 签名） | M0 AllowlistHook、M0 TickRangeHook | 暂无（Dune $0） |
| 14 | **Limit Order on Hook**（单 tick 集中度 = 限价单） | LimitOrderHook（OpenZeppelin 部署） | $125K 30d |
| 15 | **链上随机数种子**（swap 后写入 keccak256 seed 给 ERC-3232 用） | HookdRandomHook | $242K 30d |
| 16 | **聚合路由 / Kyber-style 多池路由** | Kyber hook | $94M 30d / 75 pool |
| 17 | **品牌币 Launchpad 静态费率**（pool init 时锁 fee） | Clanker Static Fee Hook | $383K 30d / 323 pool |
| 18 | **税 + 协议费 + MEV 保护组合**（多税合 1） | Token Flow Tax Hook、Aegis | $8K–145K 30d |
| 19 | **CL + am-AMM 拍卖 + FloodPlain rebalance + TWAP oracle**（v4 hook 体系天花板） | BunniHook（Bunni v2） | 主网 Ethereum 量走 Unichain/Base |
| 20 | **CL + 动态费率 + ve(3,3) 排放 + CEX-DEX 套利保护** | Ramses HL、Hybra V4 | HyperEVM 生态 |

---

## 四、Hybra V4 详细分析

> **来源**：[defillama.com/protocol/hybra-v4](https://defillama.com/protocol/hybra-v4) + 官方描述
> **链**：Hyperliquid L1（HyperEVM）
> **量级**：TVL $1.05m / 30d 交易量 $70.16m / 30d Fees $51K

### 技术栈拆解

| 维度 | 实现 | 与 Ethereum 的差异 |
|---|---|---|
| **AMM 曲线** | 集中度流动性（CL），Uniswap v3 风格 | 同 |
| **动态费率** | 实时调整（基于 volatility + volume） | 比 Ethereum 主流更激进，gas 便宜允许更高频调整 |
| **Hook 体系** | Uniswap v4-inspired hooks | HyperEVM 不直接是 v4（没有 PoolManager 部署），是自研的 hook 抽象层 |
| **排放模型** | ve(3,3) 改良版叫 **G(3,3)** | 比传统 ve(3,3) 减少强制 lockup |
| **价值分配** | Holders Revenue = 100% 走 veHYBRA 持有人 | 类似 Solidly 模式，但升级到 G(3,3) |
| **MEV 保护** | 同 Bunni 思路（surge fee + privileged arbitrage） | Hyperliquid L1 本身无 mempool，MEV 较 Ethereum 弱 |
| **跨市场** | HyperCore ↔ HyperEVM 套利原子化 | Hyperliquid 独有 |

### Hook 设计核心

- **动态费率 hook**：根据 volatility 和 volume 在每个区块内调整 fee
- **Privileged arbitrage hook**：授权特定地址做 CEX-DEX 套利，捕获的利润回到 ve 持有人
- **G(3,3) emission hook**：周期性计算 veHYBRA 权重并分发 emission

### 与 Ethereum v4 hook 的本质差异

| 维度 | Ethereum v4（Uniswap V4） | Hybra V4（HyperEVM） |
|---|---|---|
| 共识层 | 通用 EVM | HyperBFT（专用交易 L1） |
| 出块时间 | ~12s | ~0.2s |
| MEV 来源 | mempool searcher | HyperCore ↔ HyperEVM 跨域套利 |
| 池子 hook | 标准 PoolManager + hook | 自研集中度池 + hook 抽象 |
| 价值回流 | LP fee | LP fee + 协议 fee → ve 持有人 |
| 真正"反 MEV"难度 | 高（mempool 公开） | 中（无 mempool，但跨域套利可被 backend 抓到） |

### Ring 借鉴点

- **ve(3,3) 排放**：比传统 ve 更友好（无强制 lockup）——如果 Ring FewToken 想要"长期持有激励"，可以参考 G(3,3) 模式
- **Privileged arbitrage hook**：把 CEX-DEX 套利"机构化"是 HyperEVM 的核心创新；Ring 如果接 CEX/RWA 桥，类似的 hook 值得借鉴
- **动态费率激进调整**：HyperEVM gas 便宜，Ethereum 做不到每区块调 fee；Ring 在 L2 部署时可考虑类似思路

---

## 五、EulerSwap 详细分析

> **来源**：[defillama.com/protocol/eulerswap](https://defillama.com/protocol/eulerswap) + [euler-swap GitHub](https://github.com/euler-xyz/euler-swap) + [Euler docs - Maglev](https://docs.euler.finance/creator-tools/maglev/configuration/select-vault-pairs/)
> **链**：Ethereum、Unichain、BSC、Monad
> **量级**：30d 交易量 $1.6m / Cumulative $4.33B（Ethereum $3.75B，Unichain $582m）

### 核心理念：**Lending-Vault-backed AMM**

```
┌────────────────────────────────────────────────┐
│         EulerSwap 的"统一流动性"架构           │
│                                                │
│  ┌─────────────┐         ┌─────────────┐       │
│  │  Euler      │  share  │  EulerSwap  │       │
│  │  Vault A    │◄────────┤  Pool       │       │
│  │  (USDC)     │   bal   │  (USDC/WETH)│       │
│  └──────┬──────┘         └──────┬──────┘       │
│         │                       │              │
│         ▼                       ▼              │
│  ┌─────────────┐         ┌─────────────┐       │
│  │  Lending    │         │  Trader     │       │
│  │  借款人     │         │  swap       │       │
│  └─────────────┘         └─────────────┘       │
│                                                │
│  同一份 USDC 同时：                             │
│  - 在 Vault 里赚 lending interest               │
│  - 在 EulerSwap 里做 LP 赚 trading fee         │
│  - 大单来时 JIT 借出 → 无需主动 rebalance     │
└────────────────────────────────────────────────┘
```

### 技术栈拆解

| 维度 | 实现 | 与传统 v4 hook 池的差异 |
|---|---|---|
| **资产来源** | Euler 借贷金库份额（不是单独 lock） | 资本效率 100%+：LP 资产仍在 lending |
| **LP 行为** | 把资产存进 Euler vault，自动成为 LP | 不用单独 LP 池 |
| **JIT 流动性** | 大单时原子化 borrow output token 应对 | 无需 passive rebalance |
| **Hook 体系** | 集成 Uniswap v4 hook 架构 | 复用 v4 hook，但**JIT borrow 是 Euler 独有** |
| **动态 reconfigure** | hook 可调 `reconfigure()` 改 pool 参数（curve、fee、hook 配置）**不重部署** | 比普通 v4 hook 更灵活 |
| **Curve** | 自研 `CurveLib`（不是 v3 标准 x*y=k） | 支持动态曲率调整 |
| **Multi-chain** | Ethereum / Unichain / BSC / Monad | v4 标准化部署 |

### Hook 设计核心

EulerSwap 与传统 hook 的关键差异在 **hook 可以 reconfigure 池子参数**：

```solidity
// Hook 可以修改 pool 参数
function reconfigure() external {
    // 改 fee
    // 改 curve 形状
    // 改 hook 配置
    // 保留 pool 地址
}
```

`EulerSwapHooks.t.sol:373` 验证了 hook 可在 swap 后调 `reconfigure()`，改 fee / curve / hook 配置，**不重部署**。

来源：[DeepWiki - Dynamic Reconfiguration](https://deepwiki.com/euler-xyz/euler-swap/6.4-dynamic-reconfiguration)

### 4 个核心机制

1. **Lending Vault 集成**：资产不离开 Euler 借贷金库，只是 share balance 减少
2. **JIT 流动性**：大单来时通过 Euler vault 原子借出 output token
3. **Dynamic Reconfiguration**：hook 可改 pool 参数无需 redeploy
4. **Dynamic fee**：根据 JIT 借出成本动态算 fee

### 风险

- **Euler 借贷风险传染**：vault 出事 = 池子出事
- **Euler 协议已经历过黑客事件**（2023 年 $200M hack）——技术债务
- **JIT borrow 的清算风险**：极端行情下 vault 内 collateral 不足

### Ring 借鉴点

- **"借贷 + AMM"统一流动性**是未来 DeFi 大趋势（与 Fluid DEX 同路线）
- **Dynamic reconfiguration hook**（`reconfigure()` 不重部署）值得抄
- **JIT 流动性**：如果 Ring FewToken 想接 lending protocol（如 Aave、Compound）作为 backing，这种模式可直接借鉴
- **谨慎传染风险**：不能直接复刻 Euler 的"vault 单一故障点"

---

## 五补、BunniHook 详细分析

> **来源**：[`BunniHook/README.md`](file:///Users/alexla/code/ringprotocol/hooklist/docs/hooksurvey/BunniHook/README.md) + [`BunniHook` 设计原理章节](file:///Users/alexla/code/ringprotocol/hooklist/docs/hooksurvey/BunniHook/README.md#L217-L524) + Bunni v2 官方文档
> **链**：Ethereum Mainnet 主合约 + Unichain / Base / Arbitrum 多链部署
> **量级**：本调研脚本抓到的合约地址 30d 量 $0（README 自承"本部署地址可能不是生产主流实例"），主流量实际跑在 Unichain / Base

### 核心理念：**LVR 内部化 + am-AMM 拍卖 + 集中度池自动化**

Bunni v2 把"v4 集中度池"改造成一台**主动管理 LVR 的机器**——LP 不再被动承受套利者的 LVR 损失，而是通过 hook 把 LVR 拍卖给 am-AMM manager、用 surge fee 抑制极端情况、用 FloodPlain 自动 rebalance 维持区间。

```
┌──────────────────────────────────────────────────────────┐
│            BunniHook 的"主动 LVR 管理"架构              │
│                                                          │
│  ┌─────────────┐  surge   ┌──────────────┐               │
│  │  Trader     │  fee     │  am-AMM      │               │
│  │  swap       │─────┐    │  manager     │  burn if     │
│  │             │     │    │  (出价最高者)│  出价失败    │
│  └─────────────┘     ▼    └──────┬───────┘               │
│                       ▼           │                      │
│                ┌─────────────┐    │                      │
│                │  v4 集中度  │    │                      │
│                │  swap 执行  │◄───┘                      │
│                └──────┬──────┘                           │
│                       │                                  │
│                       ▼                                  │
│  Tick 偏离? ───Yes──►  ┌─────────────┐                   │
│                       │ FloodPlain  │                   │
│                       │ Dutch       │  套利者            │
│                       │ Auction     │──── 赚 LVR 回收    │
│                       └─────────────┘                   │
│                                                          │
│  LP 最终到手 = LP base fee + am-AMM bid + rebalance 后  │
│               集中度更精准带来的 fee 增量               │
└──────────────────────────────────────────────────────────┘
```

### 技术栈拆解

| 维度 | 实现 | 与普通 v4 hook 池的差异 |
|---|---|---|
| **AMM 曲线** | 集中度流动性 + 自研 LDF（Liquidity Density Function） | 不止 v3 风格的均匀 LP，可自定密度 |
| **动态费率** | **Surge fee**（指数衰减）+ base fee | 比 v4 普通 dynamic fee 多一层 LVR 抑制 |
| **拍卖机制** | **am-AMM**（链上 bonding curve 出价） | LP 把 BunniToken 抵押给 hook 参与 swap 流拍卖 |
| **Rebalance** | **FloodPlain**（外部 Dutch auction 协议） | 套利者竞争 LP 原本会被吃掉的 LVR |
| **Oracle** | 链上 TWAP（环形缓冲区） | hook 自带，不依赖 Chainlink |
| **LVR 内部化** | am-AMM bid + surge fee + rebalance 三层叠加 | 结构上把 LVR 从 LP 转给 manager |
| **Hook flags** | `afterInitialize` + `beforeAddLiquidity` + `beforeSwap` + `beforeSwapReturnsDelta` | 4 个 flag，是 v4 hook 的"少而精"配置 |
| **Hub 架构** | `BunniHub` 协调（`poolManager.setOperator(hub_, true)`） | hub 在 hook 控制下 modifyLiquidity |
| **依赖** | Solady / permit2 / biddog（AmAmm 基类） | 多个外部库，集成复杂度高 |

### Hook flags 详解

```
BunniHook 启用的 4 个 flag：

  afterInitialize         ── 必需：hub 在 init 后写入 slot0 / observation
  beforeAddLiquidity      ── 必需：hub 在 modifyLiquidity 前协调 rebalance 状态
  beforeSwap              ── 必需：动态 fee + am-AMM 核心逻辑
  beforeSwapReturnsDelta  ── 必需：useAmAmmFee 路径下推 fee 进 v4 账本

  ── 没有 ──
  afterSwap / afterAddLiquidity / beforeInitialize / beforeRemoveLiquidity
  → 极简：所有功能都通过 4 个 flag 组合完成
```

### 4 个核心机制

#### 1. Surge Fee（动态费率 + LVR 抑制）

**目的**：当 vault share price 突变偏离 → 自动抬 fee → 抑制套利者。

```solidity
// beforeSwap 内伪代码（来自 BunniHook README 设计原理章节）
if (block.timestamp >= s.slot0s[id].lastSurgeTimestamp + surgeFeeAutostartThreshold) {
    surgeFee = 0;  // 强制归零
} else {
    uint256 elapsed = block.timestamp - s.slot0s[id].lastSurgeTimestamp;
    // 指数衰减：surgeFee *= exp(-elapsed / halfLife)
    surgeFee = s.slot0s[id].lastSurgeFee * expWadDown(
        -int256(elapsed) * WAD / int256(surgeFeeHalfLife)
    );
}
swapFee = baseSwapFee + surgeFee;
```

**关键参数**（`HookParams` 部署时确定，immutable）：

| 参数 | 含义 | 典型值 |
|---|---|---|
| `surgeFeeHalfLife` | surge fee 衰减半衰期（秒） | 300-600s |
| `surgeFeeAutostartThreshold` | 多久未 surge 就强制归零 | ~1h |
| `vaultSurgeThreshold0/1` | vault share price 突变幅度触发 surge | 10-30 bps |
| `maxSwapFee` | surge 后 fee 的硬顶 | ~30 bps |

#### 2. am-AMM 竞价（链上 bonding curve）

**目的**：把"未来一段 swap 流的 fee"拍卖给 BunniToken 抵押者。**赢家接管该段 swap 的 fee，失败者 BunniToken 被 burn**。

**数据结构**（继承自 `biddog` 框架的 `AmAmm`）：

```solidity
struct AmAmmState {
    address manager;          // 当前出价最高者
    uint256 rent;             // manager 抵押的 BunniToken 数量
    uint256 deadline;         // 出价有效期
    bool enabled;             // pool 是否启用 am-AMM
}
// _K 是 immutable bonding curve 常数
// MIN_RENT = mulWadUp(K, BunniToken.totalSupply()) / MIN_RENT_DIVISOR
```

**完整生命周期**：

```
Step 1: 出价 (任何地址)
   ├─ 旧 manager 的 BunniToken 退还 / burn
   ├─ 校验 msg.value (BunniToken) >= MIN_RENT
   ├─ _pullBidToken(msg.sender, rent)
   └─ 写 s.amAmmState[id] = {manager, rent, deadline}

Step 2: 赢标 (每次 swap 走 beforeSwap)
   ├─ 读 s.amAmmState[id].manager
   ├─ if (manager != 0 && block.timestamp < deadline) {
   │      useAmAmmFee = true;
   │      amAmmFeeAmount = swapFeeAmount;
   │      return BeforeSwapDelta;
   │  }
   └─ _accrueFees(manager, currency, amAmmFeeAmount)
         → poolManager.mint(manager, currencyId, amount)

Step 3: 失败 / 到期
   ├─ if (block.timestamp >= deadline) {
   │      _burnBidToken(manager, rent);  // 永久 burn，无 refund
   │      s.amAmmState[id].manager = address(0);
   │  }
```

#### 3. FloodPlain 自动 Rebalance

**目的**：集中度 LP 偏离目标区间时，**FloodPlain 协议**通过 Dutch auction 把 rebalance 订单拍卖给套利者，**让套利者赚的 = LP 原本会被 sandwich 吃掉的 LVR**。

```solidity
// 触发条件（在 BunniHub 的 modifyLiquidity 路径中）
if (currentTick < s.slot0s[id].rangeLowerTick ||
    currentTick > s.slot0s[id].rangeUpperTick) {
    _enqueueRebalance(id);
}
```

**Dutch auction 流程**（跨多个区块）：

```
区块 N:   hub._enqueueRebalance(id)
            │  s.rebalanceOrderHash[id] = keccak(order)
            │  s.rebalanceOrderDeadline[id] = block.timestamp + 1h
            │
区块 N+1: 套利者监听 FloodPlain
            │  FloodPlain 调用 hook.rebalanceOrderPreHook(args)
            │  ├─ require keccak(args) == s.rebalanceOrderHash[id] (EIP-1271 校验)
            │  ├─ tstore output_balance_before (EIP-1153 transient)
            │  └─ poolManager.unlock(REBALANCE_PREHOOK, ...)
            │
            ▼ 套利者做 v3-style swap
            │
区块 N+2:  hook.rebalanceOrderPostHook(args)
            │  ├─ 校验 hash 仍匹配
            │  ├─ surge fee 重置（rebalance 是健康套利）
            │  ├─ orderOutputAmount = balanceOfSelf - tload(slot)
            │  └─ poolManager.unlock(REBALANCE_POSTHOOK, ...)
            ▼ 套利者赚 = LVR recapture（来自 LP 让利）
```

**关键参数**：

| 参数 | 作用 |
|---|---|
| `rebalanceMaxSlippage` | 套利者实际拿到与订单的偏差上限 |
| `rebalanceTwapSecondsAgo` | TWAP 回看窗口，校验价格合理性 |
| `rebalanceThreshold` | 偏离多少 tick 触发 rebalance |
| `rebalanceOrderDeadline` | 订单过期时间 |

#### 4. 链上 TWAP Oracle

**初始化**（`_afterInitialize` 中）：

```solidity
s.observations[id].initialize(block.timestamp, sqrtPriceX96);
s.slot0s[id].observationIndex = 0;
s.slot0s[id].observationCardinality = INITIAL_CARDINALITY;  // 通常 1024
```

**累积**（每次 swap）：

```solidity
// priceCumulative += sqrtPriceX96 * timeElapsed
s.observations[id].priceCumulative += sqrtPriceX96 * (block.timestamp - obs.lastUpdateTimestamp);
// 写入新 observation 到环形缓冲区
```

**读取**（`observe(secondsAgo)`）：

```solidity
(uint256 t0, uint256 pcum0) = _binarySearchObservation(id, secondsAgo);
(uint256 t1, uint256 pcum1) = _binarySearchObservation(id, 0);
twapSqrtPriceX96 = (pcum1 - pcum0) / (t1 - t0);  // view 函数纯链上算
```

### 4 层叠加费率结构

| 层 | 来源 | 受益方 | 大小 |
|---|---|---|---|
| 1 | LP swap fee（动态 surge 调控） | LP | baseFee + surgeFee（max ~30bps） |
| 2 | Hook fee = swapFee × hookFeeModifier / 1e6 | `hookFeeRecipient` | ~10-20% of LP fee |
| 3 | Referral reward = hookFee × referralRewardModifier / 1e6 | referrer | ~50% of hook fee |
| 4 | am-AMM bid | am-AMM manager | 整笔 LP fee（useAmAmmFee=true 时） |

**典型生产参数**：LP fee ~5 bps / hook modifier ~15% / referral ~50% / am-AMM max fee ~10 bps

### BunniHook vs Hybra V4 vs EulerSwap 三方对比

| 维度 | BunniHook | Hybra V4 | EulerSwap |
|---|---|---|---|
| **核心创新** | LVR 内部化（am-AMM） | ve(3,3) 排放 | Lending-Vault-backed |
| **MEV 抗性** | **强**（surge + am-AMM + rebalance 三层） | 中（surge + privileged arb） | 中 |
| **资本效率** | 100%（CL） | 100% | 100%+（借贷复用） |
| **LVR 处理** | **3 层叠加**（surge fee / am-AMM bid / FloodPlain rebalance） | surge fee | JIT borrow 应对 |
| **资产 backing** | LP 直接 token | LP 直接 token | Euler 借贷金库份额 |
| **Reconfigure** | 否（参数 immutable 在 HookParams） | 否 | **是**（`reconfigure()` 不重部署） |
| **Hook flags** | 4 个 | 自研抽象 | v4 + reconfigure |
| **链可移植性** | 跨链（多链已部署） | HyperEVM 专用 | 4 链已部署 |
| **代码复杂度** | **极高**（25K+ 字节，hub + hook + AmAmm + Flood） | 中 | 高 |
| **审计状态** | **无公开审计**（README 风险 13） | 待查 | Spearbit / 多次审计 |
| **运营成本** | 自营 am-AMM 拍卖 | 自营 ve 排放 | 依赖 Euler 借贷 |

### 关键风险

1. **审计缺失**：合约 25K+ 字节 + 多个外部依赖（AmAmm、Flood、Solady、permit2）但无公开审计报告（README 风险 13）
2. **Owner 单点**：`setZone` / `setHookFeeRecipient` / `setModifiers` 全是 `onlyOwner`——Owner 私钥泄露 = 改 fee 到 100%
3. **Surge fee 自动衰减**：极端行情下 `autostartThreshold` 之后 fee 强制归零，套利者集中涌入
4. **JIT MEV 盲点**：am-AMM 不管 LP 进出，仍有 JIT 流动性 MEV 暴露
5. **Dune 30d 量 0**：本调研脚本抓到的合约地址可能不是生产主流实例；Bunni v2 真正大额在 Unichain / Base
6. **`_K` immutable**：构造函数固定，bonding curve 选错 = 不可调整
7. **FloodPlain 外部依赖**：若套利者长时间不接单，pool 偏离目标区间 → IL 累积
8. **不可升级**：`upgradeable=False`，需改 fee policy 必须 redeploy + 迁移 LP

### Ring 借鉴点（已写入 summary.md S 级）

| 借鉴度 | 机制 | 怎么用 |
|---|---|---|
| ★★★★★ | **Surge fee**（指数衰减） | Few Stable 池直接抄 StableStableHook 公式，2 周可上线 |
| ★★★★★ | **am-AMM bidding** | FewToken 池装上"未来 swap 流拍卖" |
| ★★★★ | **FloodPlain rebalance** | 集中度 FewToken 池子（如果做 CL 版本） |
| ★★★ | **链上 TWAP oracle** | FewToken 池子需要 TWAP 时自研 |
| ★★ | **`afterInitialize` + `beforeAddLiquidity` 组合** | 跟 hub 协调，Ring 如果做 hub 架构可参考 |
| ★ | **Hub-only 权限** | Ring FewToken 工厂是天然"hub"，可借鉴 |

### 与 BunniHook README 的关系

- 本节是 [`BunniHook/README.md`](file:///Users/alexla/code/ringprotocol/hooklist/docs/hooksurvey/BunniHook/README.md) 的"高密度摘要"
- README 的"设计原理"章节（[L217-L524](file:///Users/alexla/code/ringprotocol/hooklist/docs/hooksurvey/BunniHook/README.md#L217-L524)）有更详细的伪代码和状态机
- README 的"风险与限制"有 16 条具体风险点，本节浓缩到 8 条最关键的

> 注：补充的伪代码基于 README 已描述的 hook flags / 接口命名（`surgeFeeHalfLife` / `vaultSurgeThreshold` / `_K` / `MIN_RENT` / `rebalanceOrderHash` 等）还原，精确字段名和函数签名需要 `cast disassemble` 主网合约验证。

---

## 六、按"价值/借鉴性"分级（与 summary.md 互补）

### S 级：已经验证 + 真的解决问题

| 技术 | 适用 Ring 场景 | 借鉴度 |
|---|---|---|
| **Surge fee（StableStableHook 模式）** | Few Stable 池子动态费率 | ★★★★★ |
| **1:1 wrap（WETHHook / WstETHHook）** | Few ETH / Few USDC 等锚定池 | ★★★★★ |
| **动态 reconfigure（EulerSwap）** | FewToken 池子参数动态调整 | ★★★★ |
| **ve(3,3) 排放（Hybra V4 模式 G(3,3)）** | FewToken 长期持有激励 | ★★★ |

### A 级：模式创新，单点强

| 技术 | 适用 Ring 场景 | 借鉴度 |
|---|---|---|
| **am-AMM 竞价（BunniHook）** | FewToken 池子 LVR 内部化 | ★★★（复杂度高） |
| **Privileged arbitrage（Hybra V4）** | 如果接 CEX/RWA 桥 | ★★ |
| **Lending-Vault 集成（EulerSwap）** | 如果 FewToken 接入 lending | ★★★★ |

### B 级：值得参考但未验证

| 技术 | 适用 Ring 场景 | 借鉴度 |
|---|---|---|
| **应用专属拍卖（Angstrom）** | 不建议——Solver 网络运营成本高 | ★ |
| **RFQ-style P2P（Sat1 Hook）** | 单一池子 $738M 体量值得研究 | ★★ |
| **LBP 启动治理（VirtualLBP）** | 如果 FewToken 做 ICO 启动 | ★★★ |
| **Launchpad 税 + 衰减税（TokenWorks）** | 新 fewToken 上市防 sniper | ★★ |

---

## 七、横向维度对比表

| 维度 | Angstrom | BunniHook | Hybra V4 | EulerSwap | StableStableHook | WETHHook |
|---|---|---|---|---|---|---|
| 价值捕获 | MEV 内化（拍卖） | LVR 内部化（am-AMM） | ve 持有人 + LP fee | LP + lending interest | LP fee | LP fee |
| 拍卖对象 | 整批订单路径 | swap 流期权 | 套利机会 | – | – | – |
| 拍卖地点 | 链下 Solver | 链上 am-AMM | 链下 backend | – | – | – |
| Hook flags 数 | 8 | 4 | 自研抽象 | v4 + reconfigure | 2 | 4 |
| LVR 抗性 | 强 | 强 | 中（surge） | 中 | 中（surge） | 弱 |
| Sandwich 抗性 | 强 | 中 | 中 | 中 | 中 | 弱 |
| JIT 抗性 | 弱 | 弱 | 弱 | 弱（JIT 是它的特色） | 弱 | 弱 |
| 资本效率 | 100% | 100% | 100% | 100%+（借贷复用） | 100% | 100% |
| 链可移植性 | 仅 Ethereum | 跨链（已部署多链） | HyperEVM 专用 | 4 链已部署 | Ethereum | Ethereum |
| 复杂度 | 极高 | 极高 | 中 | 高 | 低 | 极低 |
| Ring 借鉴度 | 思路 | 部分 | ve(3,3) | reconfigure + lending | 直接抄 | 直接抄（已在做） |

---

## 八、关键数据对比（defillama 一图看）

```
Uniswap V4            ████████████████████████████████  $615M TVL
PancakeSwap Infinity  ████                            $78M
Hydrex Omni           ▌                                $1.9M
Hybra V4              ▌                                $1.0M (本次重点)
Angstrom              ▌                                $980K (本次重点)
Alphix                ▏                                $313K
```

**说明**：
- Hybra V4 / EulerSwap 在 defillama "Hook-based AMM" 分类内属于**中等量级**
- **Uniswap V4 单家 90% TVL**——hook 经济整体仍是"巨头通吃"格局
- **Ring Few 池子**如果上 Unichain 或 HyperEVM，可以参考 Hybra V4 的 ve(3,3) 路径；如果留在 Ethereum，则重点借鉴 BunniHook + StableStableHook + WETHHook（与 summary.md 对齐）

---

## 九、参考链接

- [defillama hook-based AMM 列表](https://defillama.com/protocols/hook-based-amm)
- [Hybra V4 defillama 页](https://defillama.com/protocol/hybra-v4)
- [EulerSwap defillama 页](https://defillama.com/protocol/eulerswap)
- [euler-swap GitHub](https://github.com/euler-xyz/euler-swap)
- [Euler docs - Maglev vault pairs](https://docs.euler.finance/creator-tools/maglev/configuration/select-vault-pairs/)
- [DeepWiki EulerSwap Dynamic Reconfiguration](https://deepwiki.com/euler-xyz/euler-swap/6.4-dynamic-reconfiguration)
- [本地 hook-survey-mainnet.md](file:///Users/alexla/code/ringprotocol/hooklist/docs/hooksurvey/hook-survey-mainnet.md)
- [summary.md Ring 借鉴总览](file:///Users/alexla/code/ringprotocol/hooklist/docs/hooksurvey/summary.md)
