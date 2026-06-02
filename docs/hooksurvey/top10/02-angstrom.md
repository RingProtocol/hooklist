# Angstrom

> **地址**: [0x0000000aa232009084Bd71A5797d089AA4Edfad4](https://etherscan.io/address/0x0000000aa232009084bd71A5797d089AA4Edfad4)
> **30d 交易量**: $268.36M | **30d Swap 数**: 79450 | **Pool 数**: 2
> **审计**: [Spearbit (Sorella)](https://github.com/spearbit/portfolio/blob/master/pdfs/Sorella-Spearbit-Security-Review-October-2024.pdf)
> **源码**: [`/Users/alexla/code/uniswap/hooklist/.sources/0x0000000aa232009084bd71a5797d089aa4edfad4/`](file:///Users/alexla/code/uniswap/hooklist/.sources/0x0000000aa232009084bd71a5797d089aa4edfad4/)

## 1. 概述

Angstrom 是 Sorella Labs 出品的 **抗 MEV DEX**：
- 通过 hook 接管 Uniswap v4 池子的交易排序权
- 在 hook 内做**应用专属拍卖 (Application-Specific Auction)**
- 把 MEV 价值内化并回给 LP/交易者

**项目方**: [Sorella Labs](https://www.sorella labs.com/)

**核心特性**
- 抗三明治攻击 (Anti-Sandwich)
- 抗套利抽取 (Anti-Arbitrage)
- 降低用户实际手续费 + gas

## 2. 收益结构

| 维度 | 说明 |
|---|---|
| 收入来源 | **不直接收 LP 费**；通过拍卖捕获 MEV 价值 |
| 收益分配 | MEV 价值回给 LP + 交易者 + 协议金库（具体比例由 hook governance 配置） |
| `dynamicFee` | 是 (动态调整) |
| `requiresCustomSwapData` | 是 (需要 hookData 携带用户签名/订单信息) |
| `swapAccess` | `none` (用户可自由 swap，但需走 hook 的排序器) |

## 3. 工作原理

### 3.1 关键权限位

`getHookPermissions()` (推论自 flags):
- `beforeInitialize`, `afterInitialize`
- `beforeAddLiquidity`, `beforeRemoveLiquidity`
- `beforeSwap`, `afterSwap`
- `afterDonate`
- `afterSwapReturnsDelta`

→ 实际上**几乎全开**，需要 hook 在排序、初始化、流动性变化、swap 前后都做自定义逻辑。

### 3.2 核心机制：应用专属拍卖

```
User 提交 "intent" 订单 (含 hookData)
        ↓
Hook 在 L1 区块内运行拍卖
        ↓
  决定:
  - bundle 内交易执行顺序
  - 谁出清 (clear) 谁的订单
  - 给排序者的费用
        ↓
Hook 调用 unlockCallback 走 v4 标准 swap
        ↓
差价 (captured MEV) 分配给 LP / 用户 / 协议
```

### 3.3 关键技术点

1. **多模块拆分** (从源码目录可见)：
   - `PoolConfigStore`：池子参数存储
   - `PoolUpdates`：池子更新请求处理
   - `Settlement`：拍卖结算
   - `OrderInvalidation`：订单失效
   - `TopLevelAuth`：权限管理
   - `UnlockHook`：v4 unlock 回调

2. **签名方案**：
   - 用户订单用 EIP-712 签名
   - hook 校验签名后才将订单纳入拍卖

3. **去中心化排序**：
   - 通过 `MixedSignLib`、`X128MathLib` 等库实现价格匹配
   - 不依赖单一 sequencer

## 4. 时序图

```
User          AngstromHook      PoolManager       LP/Solver
 |                  |                |                |
 |--submitOrder()-->|                |                |
 |  (intent, hookData, signature)   |                |
 |                  |                |                |
 |                  |--deposit/credit 检查             |
 |                  |                |                |
 |                  |  (在 L1 区块内，hook 收集多个 order)  |
 |                  |                |                |
 |                  |  Solver 竞争撮合，bid 排序费       |
 |                  |                |                |
 |                  |--unlockCallback()-------------->|
 |                  |                |                |
 |                  | (内部执行多个 swap, 按拍卖结果)   |
 |                  |                |                |
 |                  |  结算 MEV 价值                  |
 |                  |  - LP 分得一部分                 |
 |                  |  - Solver 拿排序费               |
 |                  |  - User 拿 better price        |
 |                  |                |                |
 |<--settlementTx---|                |                |
```

### 4.1 时序关键点说明

| 时间点 | 事件 | 行为 |
|---|---|---|
| Order 提交 | 用户签名 order | 存入 hook 暂存区 |
| 区块打包 | Solver 提交 bundle | 拍卖出价，决定排序 |
| unlockCallback | hook 接管 v4 | 按拍卖结果执行 swap |
| 结算 | hook 分配 MEV | LP/User/Solver 按预设分账 |
| 失败回滚 | bundle 内任何 swap revert | 整个 bundle 全部 revert |

## 5. 风险

1. **依赖 Solver 网络**：如果 Solver 集合过小，可能中心化
2. **复杂签名流程**：用户体验门槛
3. **`requiresCustomSwapData = true`**：普通 router 无法直接调用
4. **升级路径**：源码无 upgradeable 标识 (按 properties)，但治理权仍在合约中

## 6. 收益估算

按 Dune Top 10 排名 #2（$268.36M/30d），单 hook 撮合了 79450 笔 swap。
- 假设平均 MEV 抽取 ~5 bps，则 30d MEV 捕获约 **$1.34M**
- 这部分价值将分给 LP/用户/协议

## 7. 总结

Angstrom 是个 **"重新设计 v4 交易顺序"的 hook**：
- 把"谁先交易"从 L1 mempool 抢跑者手里抢回来
- 通过应用专属拍卖内化 MEV
- 是 v4 上抗 MEV 设计的代表项目
- 与传统 v4 pool 不兼容 (需要 hookData)

**适用场景**：大额 swap、LP 关心抗抽取、用户能接受签名 UX。
