# UpegHook

> **地址**: [0xe54082dfbf044b6a8f584bdddb90a22d5613c440](https://etherscan.io/address/0xe54082dfbf044b6a8f584bdddb90a22d5613c440)
> **30d 交易量**: $39.80M | **30d Swap 数**: 41569 | **Pool 数**: 9
> **功能**: 存储链上 SVG 数据 + 启动 token + 每次 swap 更新随机种子

## 1. 概述

UpegHook 是 **Upeg 协议**（推测为 collectible ERC-20 / NFT 风格 token）的 hook：
- 9 个 pool
- 41569 笔 swap
- $39.80M 交易量

## 2. 功能详解（来自 hooklist description）

> "Stores on-chain SVG data for collectible ERC-20 tokens. Calls start on the configured token when first liquidity is added, and updates a random seed on each swap involving that token."

- **存储链上 SVG**：把 collectible token 的 SVG 数据存到 hook
- **首次添加流动性时调用 `start`**：启动 token 渲染
- **每次 swap 更新 random seed**：让 token 图像随 swap 随机变化

## 3. 关键权限位

```
afterAddLiquidity: true  // 首次添加流动性时启动 token
afterSwap: true          // 每次 swap 更新随机种子
```

→ **不收费**，`swapAccess: none`，是个"功能增强型 hook"。

## 4. 收益结构

- **不抽费**
- 项目方收益主要来自：
  - collectible token 的 mint fee
  - Upeg 平台服务费
  - NFT 版税

## 5. 工作原理

```
1. 首次 addLiquidity
   → hook 调用 token.start()  → 启动 token 渲染
2. swap 触发
   → hook.afterSwap()
   → hook 更新 random seed (影响 token SVG)
   → token 图像/属性变化
```

## 6. 时序图

```
User         PoolManager       UpegHook       CollectibleToken
 |                |                |                    |
 |--addLiq()---->|                |                    |
 |                |--afterAddLiq->|                    |
 |                |                |--start()--------->|
 |                |                |  (启动 token 渲染) |
 |                |                |                    |
 |--swap()------>|                |                    |
 |                |  (标准 v4 swap)                      |
 |                |--afterSwap---->|                    |
 |                |                |  (更新 random seed)|
 |                |                |  (新 SVG 数据)     |
 |<--BalanceDelta-|                |                    |
```

## 7. 总结

UpegHook 是 **"增强 collectible token 互动性"** 的 hook：
- 不抽费
- 核心价值是 token 的动态 SVG + 互动性
- 9 个 pool 表明多 token 共享一个 hook
- 适合"可玩性 > 财务收益"的场景
