# RingLPHook 概述与目标

## 1. 定位

RingLPHook 是一个**通用 LP 保护型 Dynamic Fee Hook**，面向所有代币对（any token pair），目标是：

- **抗 MEV / 抗 LVR**：通过动态费率让套利者无利可图
- **抗无常损失（IL）**：偏离越大 fee 越高，迫使价格回归
- **吸引外部 LP 资金**：收益高、资金安全、机制透明

> 与现有 9 个 Few Hook（zero-fee wrap/unwrap）不同，RingLPHook 是一个**全新通用池**，面向任意代币对，未来开放给外部 LP 存入。

## 2. 为什么做 RingLPHook

### 2.1 独立定位

现有 9 个 Few Hook（ETH/USDC/USDT/DAI/WBTC/WEETH/WSTETH/CBBTC/UNI）是 **zero-fee wrap/unwrap 专用池**，服务于 fewToken 与底层资产的 1:1 锚定兑换。它们是 Ring Protocol 生态的重要组成部分，有自身的业务价值。

RingLPHook 的定位与之**完全不同且互补**：

- Few Hook：zero-fee，服务特定锚定资产对的 wrap/unwrap
- RingLPHook：通用动态费率保护，**面向任意代币对**，吸引外部 LP 资金，通过机制设计实现抗 MEV / 抗 IL

### 2.2 市场机会

Uniswap V4 上线后，动态 fee hook 赛道还没有**面向任意 pair 的成熟 LP 保护方案**：

- `StableStableHook`：只针对强锚定稳定币对
- `EMADynamicFeeHook`：算法好但缺乏 surge 保护
- `BunniHook`：功能完整但过度复杂，依赖外部协议
- `Angstrom`：需要自建 Solver 网络，运营成本极高

**空隙 = "简单但有效" 的通用动态 fee hook**

### 2.3 目标用户

| 用户 | 需求 |
|---|---|
| 外部 LP | 寻找"收益比 v3/v4 标准池高、风险可控"的池子 |
| 交易者 | 正常交易时 fee 低，只在市场混乱时 fee 升高 |

## 3. 设计哲学

| 原则 | 说明 |
|---|---|
| **简单优先** | 不做 Angstrom/Bunni 级别的复杂系统，核心算法一行公式 |
| **完全 on-chain** | 不依赖外部预言机、不依赖链下 Solver |
| **LP 收益最大化** | Phase 1 100% fee 给 LP，不收 protocol fee |
| **Immutable 核心** | 费率公式、EMA 参数部署后不可改，防止治理攻击 |
| **可组合** | 三层模块化设计，未来可叠加新机制 |

## 4. 核心目标总结

| 目标 | 实现方式 |
|---|---|
| 抗 MEV | 方向性 fee + repeat-swap penalty + surge 熔断 |
| 抗 IL | EMA 偏离度 × 指数惩罚，偏离越大 fee 越狠 |
| 吸引外部 LP | 高 fee 时期 LP 收益高 + 无 protocol 抽成 + 资金安全 |
| 通用任意 pair | EMA 自参考，不需要外部锚定价格 |

## 5. 不做的事（明确排除）

| 不做 | 原因 |
|---|---|
| Angstrom 级拍卖 | 需要自建 Solver 网络 + EIP-712 订单簿，运营成本远超 LP 收益增量 |
| am-AMM 押金竞价 | 对低频交易对冷启动失败，押金管理增加 LP 认知成本 |
| FloodPlain rebalance | RingLPHook 不是集中流动性（CL）池，不需要自动 rebalance |
| 链下 KYC / ACL | M0 模式，违背"完全开放吸引外部 LP"的目标 |
| Protocol fee | Phase 1 不收，最大化 LP APY 吸引流动性 |

---

*下一篇：[02-HOOK_SURVEY_COMPARISON.md](02-HOOK_SURVEY_COMPARISON.md) — 50+ hook 横向对比与选择逻辑*
