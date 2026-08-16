# EMADynamicFeeHook 详解

## 1. 基本信息

| 字段 | 值 |
|---|---|
| 合约名 | `EMADynamicFeeHook` |
| Ethereum | `0x924e5C44c3b82C2C0Ba231Cd0De7B581180E1bC0` |
| Arbitrum | `0xe025cb6c58826ac79e2052c350250881f8f51bc0` |
| Optimism | `0xb1db44de89634a001ceb5847defc3ff1e5601bc0` |
| Polygon | `0x8eB0089d6c616bC2b7f69b3CAFECfEDc3eF11BC0` |
| Unichain | `0x6398f3c67b03c4622bdaa48d9e340d66e23a1bc0` |
| 部署方 | `0xbE048D30fa1b5144694D33f8bd482D469028Da99` |
| 源码 | 已验证 (Etherscan) |
| 审计 | 无 |
| Owner/Admin | **无** — 完全 immutable |
| 可升级 | 否 |
| 代码行数 | ~170 行 |

## 2. Hook 权限位

```
beforeInitialize:  false
afterInitialize:    true   ← 初始化 EMA
beforeAddLiquidity: true   ← 记录 LP 加仓 block（Anti-JIT）
afterAddLiquidity:  false
beforeRemoveLiquidity: true  ← Anti-JIT 检查
afterRemoveLiquidity:  true  ← 清理 Anti-JIT 记录
beforeSwap:   true   ← 计算动态 fee
afterSwap:    true   ← 更新 EMA
beforeDonate: false
afterDonate:  false
*ReturnsDelta: 全部 false（不修改 swap delta，纯 fee 覆盖）
```

**关键点**：所有 `*ReturnsDelta` 都是 false，意味着这个 hook **只覆盖 fee，不改变 swap 的 token 流向**。这是最安全的 hook 类型——它不会"偷"你的 token，只是告诉 PoolManager "这笔 swap 用这个费率"。

## 3. 核心算法

### 3.1 EMA 价格更新

```solidity
uint256 constant ALPHA_NUM = 8;
uint256 constant ALPHA_DENOM = 100;
// α = 0.08（8% 权重给新价格）

newEma = currentPrice * 0.08 + oldEma * 0.92
```

- α = 0.08 是一个温和的平滑系数
- EMA 滞后性：价格突变时 EMA 移动缓慢，因此 `deviation` 会变大 → fee 升高
- 价格回归时 EMA 缓慢追上，`deviation` 缩小 → fee 降低

### 3.2 偏离度计算

```solidity
diff = |sqrtPriceX96 - ema|
deltaBps = diff * 10000 / ema   // 以基点(bps)表示的偏离度
if (deltaBps > 10000) deltaBps = 10000  // cap at 100%
```

- `deltaBps = 100` 表示偏离 1%
- `deltaBps = 10000` 表示偏离 100%（已 cap）

### 3.3 30 档费率查表

| 偏离区间 (bps) | fee (bps) | 实际费率 | 档位说明 |
|---|---|---|---|
| 0-1 | 100 | 0.01% | ultra-low（11 档，headroom 35%） |
| 1-2 | 130 | 0.013% | |
| 2-3 | 195 | 0.020% | |
| ... | ... | ... | |
| 15-18 | 1170 | 0.117% | |
| 18-22 | 1430 | 0.143% | low-mid（9 档） |
| ... | ... | ... | |
| 65-72 | 4680 | 0.468% | |
| 72-90 | 6500 | 0.650% | upper（10 档） |
| ... | ... | ... | |
| 300-380 | 26000 | 2.600% | |
| ≥380 | 30000 | 3.000% | MAX_FEE |

**设计特点**：
- 低偏离区档位密集（0.01% → 0.12% 有 11 档），正常交易时 fee 极低，不赶走交易者
- 高偏离区档位稀疏但 fee 跳跃大，套利者利润被快速压缩
- 最大 3% fee，足以让大多数套利无利可图

### 3.4 Anti-JIT 保护

```solidity
uint256 constant ANTI_JIT_BLOCKS = 300;

// beforeAddLiquidity: 记录 tx.origin 加仓的 block
liquidityAddedBlock[poolId][tx.origin] = block.number;

// beforeRemoveLiquidity: 检查是否过了 300 blocks
require(addedBlock == 0 || block.number >= addedBlock + 300, "anti-JIT cooldown");

// afterRemoveLiquidity: 清理记录
delete liquidityAddedBlock[poolId][tx.origin];
```

- JIT（Just-In-Time）LP：在交易前加仓、交易后立即撤仓，抢夺交易者 fee
- 300 blocks ≈ 1 小时（Ethereum，12s/block），强制 LP 至少持仓 1 小时
- 用 `tx.origin` 而非 `msg.sender`，防止合约中转绕过

## 4. 工作时序

```
┌─────────────────────────────────────────────────────────┐
│  Pool 初始化                                              │
│  afterInitialize: emaSqrtPrice[poolId] = sqrtPriceX96   │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  LP 加流动性                                              │
│  beforeAddLiquidity: 记录 block.number                   │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  Swap 发生                                                │
│  beforeSwap:                                              │
│    1. 读取 ema & current sqrtPriceX96                    │
│    2. 计算 deltaBps = |current - ema| / ema * 10000      │
│    3. 查表得到 fee                                        │
│    4. 返回 fee | OVERRIDE_FEE_FLAG                       │
│  → PoolManager 用此 fee 执行 swap                         │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  Swap 结束                                                │
│  afterSwap:                                               │
│    1. 读取 ema & new sqrtPriceX96                        │
│    2. newEma = current*0.08 + oldEma*0.92                │
│    3. 存储 newEma                                         │
│    4. emit SwapFeeUpdated(poolId, fee, deltaBps, newEma) │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  LP 撤流动性                                              │
│  beforeRemoveLiquidity:                                   │
│    require(block.number >= addedBlock + 300)             │
│  afterRemoveLiquidity:                                    │
│    delete liquidityAddedBlock[poolId][tx.origin]         │
└─────────────────────────────────────────────────────────┘
```

## 5. 安全分析

### 5.1 优点

| 维度 | 说明 |
|---|---|
| **Immutable** | 无 owner、无 admin、无升级机制。部署后不可改，LP 无需信任任何方 |
| **无外部依赖** | 不依赖 Chainlink、不依赖链下 Solver、不依赖其他协议 |
| **纯 fee 覆盖** | `*ReturnsDelta` 全 false，不修改 swap token 流向，不会"偷"token |
| **任意 pair** | EMA 自参考，ETH/USDC、TOKENA/TOKENB、稳定币对都能用 |
| **标准 swap** | 不需要 custom swap data，Universal Router 直接兼容 |
| **溢出保护** | EMA 更新先除后乘避免 uint160 溢出；deltaBps cap at 10000 |

### 5.2 已知局限

| 局限 | 影响 | 缓解 |
|---|---|---|
| **无 surge 机制** | 闪电贷瞬间砸盘时，EMA 还来不及反应，第一笔可能用低 fee | 单笔套利利润有限；后续 swap 的 EMA 偏离会迅速拉高 fee |
| **Anti-JIT 用 tx.origin** | tx.origin 可被 Flashbots bundle 中的中间合约"继承" | 实际影响小，JIT LP 通常直接用 EOA |
| **无 audit** | 未经过第三方审计 | 代码仅 ~170 行，可自行审计；多链部署一致性可验证 |
| **fee 查表是阶梯式** | 非连续平滑，边界处有跳变 | 跳变方向是"偏离越大 fee 越高"，对 LP 有利 |
| **EMA α 固定 0.08** | 不可调，可能不适合所有 pair | 0.08 是合理默认值；如需自定义可 fork 修改 |

### 5.3 风险评估

| 风险 | 等级 | 说明 |
|---|---|---|
|  rug pull | **无** | 无 owner，无法抽走资金 |
| 参数篡改 | **无** | immutable，无法改 fee 公式 |
| 升级攻击 | **无** | 不可升级 |
| 预言机操纵 | **无** | 不用外部预言机 |
| 重入攻击 | **低** | 无 *ReturnsDelta，不直接处理 token 转账 |
| 整数溢出 | **低** | 先除后乘 + cap，Solidity 0.8.x 内置检查 |

## 6. 多链部署一致性

EMADynamicFeeHook 在 5 条链上部署，源码描述完全一致。可以交叉验证：

| 链 | 地址 | 描述关键词 |
|---|---|---|
| ethereum | `0x924e5...1bC0` | EMA, 30-step, 0.01%-3.00%, 300-block anti-JIT |
| arbitrum | `0xe025cb...1bc0` | 同上 |
| optimism | `0xb1db44...1bc0` | 同上 |
| polygon | `0x8eB008...11BC0` | 同上 |
| unichain | `0x6398f3...1bc0` | 同上 |

> 如果你的目标链已有部署，**直接用已部署地址即可**，无需自己部署。见 [04-DEPLOYMENT_GUIDE.md](04-DEPLOYMENT_GUIDE.md)。

## 7. 源码

完整源码见 [`src/EMADynamicFeeHook.sol`](../src/EMADynamicFeeHook.sol)，依赖 [`src/BaseHook.sol`](../src/BaseHook.sol)（OpenZeppelin uniswap-hooks）。

---

*下一篇：[04-DEPLOYMENT_GUIDE.md](04-DEPLOYMENT_GUIDE.md) — 部署与配置指南*
