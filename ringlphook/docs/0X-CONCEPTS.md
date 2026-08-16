# RingLPHook 核心概念

本文档解释 RingLPHook 设计中涉及的关键概念，供团队成员快速理解。

---

## 1. JIT (Just-In-Time Liquidity)

### 1.1 什么是 JIT？

**JIT = 刚好及时的流动性**。在 DeFi 语境下，它指一种**寄生型套利攻击**：

套利者看到 mempool 中有一笔即将执行的大额 swap（对价格影响很大的交易），于是：

1. **加流动性**：在同一个 block 内调用 `addLiquidity`，向 pool 注入大量流动性
2. **吃差价**：利用这笔大额 swap 造成的价差，用自己的流动性完成套利 swap
3. **撤流动性**：在同一个 block 内调用 `removeLiquidity`，把注入的流动性全部撤出

整个过程在**同一个 block 内完成**，套利者**不承担任何持仓风险**。

### 1.2 为什么 JIT 对 LP 有害？

假设 pool 里有 Alice（真实 LP）的 $100K 流动性。

- **没有 JIT 时**：大额 swap 使用 Alice 的流动性，Alice 收取 0.3% 的 swap fee
- **有 JIT 时**：套利者 Bob 临时加入 $500K 流动性，抢走了大部分 swap fee，然后撤走。Alice 的 fee 收入被稀释，且承担了更大的无常损失（因为 Bob 的流动性让价格变动更剧烈，而 Bob 不承担后续风险）

**结果**：真实 LP 赚得更少，风险更大。

### 1.2.1 数字示例

**Pool 状态**：
- ETH/USDC pool，ETH 价格 = $1000
- 流动性：Alice 提供了 50 ETH + 50,000 USDC（TVL = $100K）

**场景：一笔 10 ETH 的大额 swap 进来**

#### 没有 JIT（只有 Alice 的 $100K 流动性）

- 10 ETH 占 pool 的 20%，滑点较大
- swap 后价格从 $1000 → $960（-4%）
- Alice 收取 swap fee：0.05% × $10,000 = **$5**
- Alice 的流动性承担了全部价格波动

#### 有 JIT（Bob 临时加入 $400K 流动性）

Bob 在同一 block 内：
1. **addLiquidity**：注入 200 ETH + 200,000 USDC，pool TVL 变成 $500K
2. **大额 swap 执行**：10 ETH 只占 pool 的 4%，滑点很小
   - 价格只从 $1000 → $996（-0.4%）
   - swap fee 按流动性占比分配：
     - Bob 占 80%（$400K/$500K）→ 得 fee = **$4**
     - Alice 占 20%（$100K/$500K）→ 得 fee = **$1**
3. **removeLiquidity**：Bob 撤出全部 $400K，fee 收入 $4 带走

**对比**：

| 指标 | 无 JIT | 有 JIT |
|---|---|---|
| Alice 的 fee 收入 | $5 | $1（-80%）|
| 价格变动 | -4%（大） | -0.4%（小） |
| Alice 的 IL | 较大 | 较小 |
| Bob 净收益 | 0 | $4（零风险） |

**表面矛盾**：Alice 的 IL 变小了（因为 Bob 稀释了价格变动），但 fee 收入暴跌 80%。

**实际损失**：
- Alice 存入 pool 的核心目的通常是**赚 fee**，不是**避免 IL**
- 如果 Alice 只想持有 ETH，她不需要来 DeFi 做 LP
- fee 收入从 $5 → $1，意味着 Alice 的**年化收益**直接打了 2 折
- 而 Bob 拿走了本属于 Alice 的 $4 fee，不承担任何后续风险

**更极端的情况**：
- 如果下一笔交易是反向（USDC → ETH），价格从 $996 → $1004
- 由于 Bob 已经撤走，这笔反向 swap 的 fee 又大部分被 Alice "补贴"了
- Bob 在价格高位退出，Alice 在价格低位被"接盘"

**总结**：JIT 不是让 LP "少赚一点"，而是让**寄生者白嫖 LP 的流动性基础设施**，把 LP 变成免费工具。

### 1.3 RingLPHook 如何防御 JIT？

**300 block cooldown 机制**：

```solidity
function beforeAddLiquidity(...) {
    // 记录存入 block
    s.depositBlock[msg.sender] = block.number;
}

function beforeRemoveLiquidity(...) {
    // 300 block 内禁止撤出
    require(block.number >= s.depositBlock[msg.sender] + 300, "JIT cooldown");
}
```

**逻辑**：
- 如果 Bob 想 JIT，他必须在同一个 block 内 add + swap + remove
- 但 `removeLiquidity` 会被拒绝（deposit 未满 300 blocks）
- Bob 的流动性被"锁定"在 pool 中至少 300 blocks（~1 小时）
- 在这 1 小时内，如果价格反向波动，Bob 承担无常损失
- **JIT 从"零风险套利"变成"高风险持仓"，套利者自然放弃**

### 1.4 为什么选 300 blocks？

| 参数 | 数值 | 理由 |
|---|---|---|
| 300 blocks | ~1 小时（12s/block） | 足够覆盖 mempool 观察→执行→确认的完整套利窗口 |
| 不选更短（如 10 blocks） | 套利者可以等 2 分钟再撤 | 无法有效阻止 |
| 不选更长（如 1000 blocks） | 真实 LP 也受影响 | 降低流动性灵活性 |

**参考**：EMADynamicFeeHook（已部署主网）采用 300 blocks，经过实战验证。

### 1.5 JIT 与 MEV 的关系

| 概念 | 区别 |
|---|---|
| **Sandwich Attack（三明治攻击）** | 在 victim 交易前后各做一笔交易，利用价格变动获利 |
| **JIT** | 临时加入流动性，利用 pool 的大额交易获利，不承担持仓风险 |
| **共同点** | 都利用了交易顺序和流动性的信息优势 |

RingLPHook 同时防御两者：
- **JIT**：300 block cooldown
- **Sandwich**：高 dynamic fee + repeat-swap penalty

---

*本文档会根据需要持续补充更多核心概念。*
