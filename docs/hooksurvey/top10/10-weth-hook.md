# WETH Hook (Uniswap 官方)

> **地址**: [0x57991106cb7aa27e2771beda0d6522f68524a888](https://etherscan.io/address/0x57991106cb7aa27e2771beda0d6522f68524a888)
> **30d 交易量**: $18.09M | **30d Swap 数**: 15860 | **Pool 数**: 1
> **Dune label**: Uniswap
> **源码**: [`/Users/alexla/code/uniswap/hooklist/.sources/0x5799...8888/`](file:///Users/alexla/code/uniswap/hooklist/.sources/0x57991106cb7aa27e2771beda0d6522f68524a888/)

## 1. 概述

WETH Hook 是 **Uniswap 官方** v4 提供的 ETH/WETH 包装 hook：
- 让 ETH 和 WETH 在 v4 池子里能**1:1 无缝转换**
- 用户可以 `swap(ETH → Token)` 而不需要先 wrap 成 WETH
- 15860 笔 swap, 单笔均价 ~$1140

## 2. 收益结构

- **不抽任何费用**
- `swapAccess: none`, 完全公开

## 3. 工作原理

### 3.1 关键权限位

```
beforeInitialize: true   // 校验 ETH/WETH 对
beforeAddLiquidity: true // 校验
beforeSwap: true         // 处理 wrap/unwrap
beforeSwapReturnsDelta: true // 通过 delta 机制处理包装
```

### 3.2 核心机制

```
用户 send ETH → PoolManager
  ↓
hook.beforeSwap()
  - 检测: 输入是 ETH (Currency == address(0))
  - deposit ETH to WETH contract
  - return BeforeSwapDelta(delta0=-amount, delta1=0)  // 把 ETH 从 pool "取走"
  ↓
v4 走标准 swap (WETH ↔ Token)
  ↓
hook 在内部维护 WETH ↔ ETH 平衡
```

## 4. 时序图

```
User         PoolManager       WETHHook        WETH9 Contract
 |                |                |                  |
 |--swap(ETH->T)---->|                |                  |
 |  (附带 ETH)   |                |                  |
 |                |--beforeSwap()-->|                  |
 |                |                |                  |
 |                |  (检测: input 是 ETH)               |
 |                |                |--deposit(ETH)--->|
 |                |                |<--WETH amount----|
 |                |                |                  |
 |                |<--selector, BeforeSwapDelta(-ETH, 0)--|
 |                |                |                  |
 |                | (v4 标准 WETH↔Token 撮合)         |
 |                |                |                  |
 |                |  (如果输出是 ETH，则 withdraw)     |
 |                |                |--withdraw(ETH)-->|
 |                |                |                  |
 |<--ETH + Tokens-|                |                  |
```

## 5. 风险

- **gas 成本略高**：因为多了一次 wrap/unwrap
- **支持 bot 套利**：单 pool 15860 笔 swap 表明可能有高频 bot 利用
- **gas 补贴模式**：适合用 paymaster

## 6. 总结

- Uniswap 官方 ETH/WETH 兼容层
- 解决 v4 native ETH 的关键问题
- 1 个 pool 15860 笔 swap，撮合效率很高
- 适合所有需要"原生 ETH 体验"的 dApp
