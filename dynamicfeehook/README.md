# DynamicFeeHook — 可直接部署的动态费率 Hook

本目录汇总了 hooklist 中所有支持 `dynamicFee` 的 hook，并从中选出一个**最靠谱、可直接配置到任意池子仓位**的方案：**EMADynamicFeeHook**。

## 推荐方案：EMADynamicFeeHook

| 维度 | 值 |
|---|---|
| 合约 | `EMADynamicFeeHook` |
| Ethereum 主网地址 | `0x924e5C44c3b82C2C0Ba231Cd0De7B581180E1bC0` |
| 链 | Ethereum / Arbitrum / Optimism / Polygon / Unichain（已多链部署） |
| 源码 | 已验证 (verified on Etherscan) |
| Owner / Admin | **无** — 完全 immutable |
| 可升级 | 否 |
| 任意 pair | 是（EMA 自参考，不需要外部锚定价格） |
| Anti-JIT | 300 blocks cooldown |
| 费率范围 | 0.01% → 3.00%（30 档阶梯） |
| swapAccess | `none`（任何人可 swap） |
| requiresCustomSwapData | 否（标准 swap 即可） |
| 代码量 | ~170 行核心逻辑 |

### 为什么选它

1. **完全 immutable** — 无 owner、无 admin、无升级机制。部署后费率公式不可篡改，LP 敢存大钱。
2. **任意 pair 通用** — EMA 是"自参考"的，不需要知道"正确价格"，ETH/USDC、TOKENA/TOKENB 都能用。
3. **极简** — 仅依赖 OpenZeppelin `BaseHook` + Uniswap v4 core，无外部预言机、无 Solver 网络。
4. **已多链部署验证** — Ethereum、Arbitrum、Optimism、Polygon、Unichain 都有同一合约的部署，源码一致。
5. **标准 swap 兼容** — `requiresCustomSwapData = false`，Universal Router / 1inch / MetaMask 等普通路由可直接调用。

## 目录结构

```
dynamicfeehook/
├── README.md                          # 本文件
├── docs/
│   ├── 01-OVERVIEW.md                 # 动态费率 hook 概述
│   ├── 02-HOOK_SURVEY.md              # 68 个 dynamic fee hook 横向对比
│   ├── 03-EMA_DYNAMIC_FEE_HOOK.md     # EMADynamicFeeHook 详解
│   └── 04-DEPLOYMENT_GUIDE.md         # 部署与配置指南
├── src/
│   ├── EMADynamicFeeHook.sol          # 主合约源码（已验证）
│   └── BaseHook.sol                   # OpenZeppelin BaseHook 依赖
└── hooks-dynamic-fee.json             # 全部 68 个 dynamic fee hook 列表
```

## 快速使用

如果你只想**直接用已部署的合约**（推荐，省去部署步骤）：

1. 找到目标链上已部署的 `EMADynamicFeeHook` 地址（见 [03-EMA_DYNAMIC_FEE_HOOK.md](docs/03-EMA_DYNAMIC_FEE_HOOK.md)）
2. 用该 hook 地址初始化你的 Pool（见 [04-DEPLOYMENT_GUIDE.md](docs/04-DEPLOYMENT_GUIDE.md)）
3. 添加流动性，开始交易

如果你想**自己部署一份**（适合自定义费率档位）：

```bash
# Foundry 项目结构
forge install OpenZeppelin/openzeppelin-uniswap-hooks
forge install Uniswap/v4-core
forge install Uniswap/v4-periphery

# 部署（需要先部署/获取 PoolManager 地址）
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
```

详见 [04-DEPLOYMENT_GUIDE.md](docs/04-DEPLOYMENT_GUIDE.md)。

---

*源码来源：Etherscan 已验证合约，原始路径 `sources/0x924e5c44.../src_EMADynamicFeeHook.sol`*
