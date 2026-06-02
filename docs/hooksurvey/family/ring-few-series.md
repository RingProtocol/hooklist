# Ring Few 系列 Hook 合并调研

> **系列定位**: Ring Protocol 的 "fewToken" 包装 hook
> **核心机制**: 1:1 包装底层 ERC20 ↔ fewToken，在 Uniswap v4 swap 中**原子化**完成 wrap/unwrap
> **覆盖版本**: ETH, USDC, USDT, WBTC, CBBTC, DAI, UNI, WEETH, WSTETH

## 1. 概述

Ring Protocol 是一个 **fewToken wrapping protocol**，提供不同 ERC20 的 1:1 包装层。在 v4 上的实现是"hook 在 swap 时自动 wrap/unwrap"。

**项目方**: [Ring Protocol](https://ring.exchange/)

## 2. 覆盖的 Hook 列表

| 简称 | 完整名 | 地址 (Etherscan 跳转) | 30d 交易量 | Swap 数 | Pool |
|---|---|---|---|---|---|
| ETH | Ring Few ETH Hook | [0x0443...6888](https://etherscan.io/address/0x044301939deb7ca53c4733dd4d9b3bc5ea0c6888) | $172.86K | 271 | 1 |
| WBTC | Ring Few WBTC Hook | [0x0fe9...2888](https://etherscan.io/address/0x0fe942afdb2f51e25cbf892aad175c6a574f2888) | $179.53K | 9 | 1 |
| CBBTC | Ring Few CBBTC Hook | [0x8347...2888](https://etherscan.io/address/0x8347b7a3807c681513d2b51b8223e59aa16a2888) | $73.65K | 3 | 1 |
| USDC | Ring Few USDC Hook | [0x4b2e...2888](https://etherscan.io/address/0x4b2eb653d13e6c9ac5a0a01fde22f2c8d6592888) | $60.89K | 36 | 1 |
| DAI | Ring Few DAI Hook (Ethereum) | [0x85b6...e888](https://etherscan.io/address/0x85b648a64aed6307d5d5ce26e6ae086c17bde888) | $34.67K | 1 | 1 |
| USDT | Ring Few USDT Hook | [0xbadf...6888](https://etherscan.io/address/0xbadf77d50478b4432ef1f243b9c0bc7869486888) | $136.78K | 52 | 1 |
| UNI | Ring Few UNI Hook | (hooks/ethereum 收录) | (见 README) | (见 README) | 1 |
| WEETH | Ring Few WEETH Hook (Ethereum) | (hooks/ethereum 收录) | (见 README) | (见 README) | 1 |
| WSTETH | Ring Few WSTETH Hook (Ethereum) | (hooks/ethereum 收录) | (见 README) | (见 README) | 1 |

> 部分 hook 在 Dune 排行榜交易量较小，单列性价比低，故统一在本系列文档中介绍。

## 3. 收益结构

- **不抽任何费用** (`swapAccess: none`)
- 项目方收益主要来自：
  - **Few token 铸币/赎回费**
  - **Ring Protocol 协议治理代币分发**
  - 间接来自 wrapped 资产 TVL 增长

## 4. 工作原理

### 4.1 关键权限位（统一模式）

```
beforeInitialize: true   // 校验池子只能由 FewTokenFactory 创建
beforeAddLiquidity: true // 校验只能加 fewToken
beforeSwap: true         // 处理 wrap/unwrap
beforeSwapReturnsDelta: true // 通过 delta 机制处理 wrap
```

### 4.2 核心机制

```
User 想用 USDC swap fewUSDC
  ↓
hook.beforeSwap()
  - 检测: 输入 currency0 == fewUSDC, 输出 currency1 == USDC
  - 或反过来
  ↓
hook 通过 beforeSwapReturnsDelta 调整 delta
  - 把 fewUSDC 销毁
  - 把对应 USDC 释放到 pool
  ↓
v4 标准 swap 走 USDC ↔ 另一个 token
  ↓
如果输出是 fewUSDC，则 wrap 一次 USDC → fewUSDC
```

### 4.3 关键文件 (从 ETH hook 源码推断)

- `src_hooks_FewTokenHook.sol` (基类)
- `src_hooks_FewETHHook.sol` (ETH 专用)
- `src_base_DeltaResolver.sol` (delta 处理)
- `src_interfaces_external_IFewWrappedToken.sol` (fewToken 接口)

## 5. 时序图（以 ETH hook 为例）

```
User         PoolManager       FewETHHook       fwWETH Contract
 |                |                |                   |
 |--swap(ETH->Token)-->|            |                   |
 | (附带 ETH)   |                |                   |
 |                |--beforeSwap()->|                   |
 |                |                |                   |
 |                |  (检测: currency0 == ETH)          |
 |                |                |--deposit(ETH)---->|
 |                |                |<--fwWETH--------|
 |                |                |                   |
 |                |<--selector, BeforeSwapDelta(-ETH, 0)--|
 |                |                |                   |
 |                |  (v4 走 fwWETH↔Token 撮合)         |
 |                |                |                   |
 |<--Tokens------|                |                   |
```

## 6. 风险

1. **每多一个 fewToken 都需要一个 hook 部署**（gas 成本 + 治理面）
2. **底层 token 与 fewToken 必须严格 1:1**，如果 wrapped 资产出问题，hook 也跟着
3. **升级路径不透明**（如 properties.upgradeable）

## 7. 系列特征总结

| 维度 | Ring Few 系列 |
|---|---|
| Hook 数 | 7+ (按 token 分) |
| 抽费 | ❌ |
| 业务 | fewToken wrapping |
| 项目方 | Ring Protocol |
| 关键风险 | 依赖 fewToken 1:1 锚定 |
| 适用场景 | 用户希望持有 wrapped 形式 + 同时能在 v4 上自由 swap |

## 8. 总结

Ring Few 是 **"资产包装"** 类 hook 的代表：
- 不抽费
- 通过 hook 让 v4 池"看"起来是原生 fewToken
- 7+ 个 token 各自独立 hook（因为 v4 权限位要地址 bitmask 匹配）
- 适合做"LST wrapper / BTC wrapper / Stable wrapper"等场景
