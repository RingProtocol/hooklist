# Angstrom

> **地址**: [0x0000000aa232009084Bd71A5797d089AA4Edfad4](https://etherscan.io/address/0x0000000aa232009084Bd71A5797d089AA4Edfad4)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: https://github.com/spearbit/portfolio/blob/master/pdfs/Sorella-Spearbit-Security-Review-October-2024.pdf
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | Angstrom |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $268M |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeInitialize`, `afterInitialize`, `beforeAddLiquidity`, `beforeRemoveLiquidity`, `beforeSwap`, `afterSwap`, `afterDonate`, `afterSwapReturnsDelta`

## 属性

`dynamicFee=True` `requiresCustomSwapData=True` `swapAccess=none`

## 功能描述

Angstrom is a decentralized exchange that takes control of its transaction ordering, preventing value extraction from liquidity providers and traders. By running application-specific auctions, Angstrom internalizes MEV and redirects the extracted value back to users, preventing arbitrage losses and sandwich attacks while reducing trading fees and gas.

## 调研结果

### 收益结构

Angstrom 的核心是**把 MEV 从套利者手中夺回，重新分配给 LP 和 trader**——它不是一个普通的 swap 池，而是一台"应用专属拍卖 + Uniswap v4 池"的混合体。

| 层 | 来源 | 受益方 |
|---|---|---|
| 1 | Uniswap v4 标准 LP swap fee | LP（基础收益） |
| 2 | 应用专属拍卖（app-specific auction）获胜者出价 | **LP**（= 把原本被套利者赚走的 LVR 内部化） |
| 3 | 拍卖中未中标订单的负滑点 / 罚金 | 协议金库 / 反作弊池 |
| 4 | 自定义 swap data 中的 `requiresCustomSwapData` 强制校验 | 防止外部 MEV searcher 截胡拍卖 |

**关键点**：传统 v4 hook 只在 swap 发生瞬间改 fee、扣 LVR；Angstrom 是**在 swap 到达 mempool 之前就完成拍卖**——trader 提交订单时，Angstrom 的 Solver 网络先内部撮合，能 internalize 的就 internalize，剩余的才进 v4 池子，并按池子最优路径出价。

**典型费率（生产部署样本，Dune 推算）**：
- LP base fee：~5 bps（与 v4 标准 500 / 1e6 一致）
- 拍卖获胜者的 LP 加成：每次拍卖独立定价，**LP 实际到手显著高于 base fee**（这是 Angstrom 跑出 $268M 量级的根因）
- Trader 端：gas 成本降低（不依赖外部 searcher 帮自己 anti-sandwich）

### 工作原理

**Angstrom 是 v4 hook 体系里最不像"传统 hook"的一个**——它把整个交易排序权抢过来，自己当"应用专属 PBS"。

**核心组件**：

1. **`AngstromHook`（本合约）**：作为 v4 hook 守门员，所有 swap / liquidity / donate 都先过 hook 一遍。
2. **Solver 网络（外部）**：链下 Solver 竞标出价，决定哪些订单 internalize、哪些走 v4 池子。
3. **`requiresCustomSwapData=true`**：强制 swap 必须携带 `IAngstrom.SwapParameters`（订单 + Solver 签名），普通 `poolManager.swap` 直接 revert——这是"独占排序权"的密码学锁。
4. **`afterSwapReturnsDelta`**：hook 在 swap 结束后还能推回 delta，用于把拍卖获胜者的"额外 fee"mint 到 hook / LP。
5. **`afterDonate`**：保留 donate 路径——协议可主动注入流动性激励或回填拍卖罚金。

**Hook flags**（最完整的一档）：
- `beforeInitialize` / `afterInitialize`：控制谁能初始化池子（Angstrom 通常自己部署）
- `beforeAddLiquidity` / `beforeRemoveLiquidity`：LP 进入/退出时同步 auction 状态
- `beforeSwap` / `afterSwap`：核心拍卖逻辑 + delta 推送
- `afterDonate`：协议激励
- `afterSwapReturnsDelta=true`：与 BunniHook 同款，但用法是"把拍卖 fee 推回 v4 账本"

**`requiresCustomSwapData` 含义**：
- 拒绝任何不携带 Angstrom 特定 calldata 的 swap
- 这就阻断了"普通 searcher 监听 mempool 后插队"——外部人想套利 Angstrom 池，必须先得到 Angstrom 的 Solver 签
- 本质上是**用 EIP-712 + hook 校验替代 mempool PBS**

**审计**：Spearbit 2024-10 报告（[Sorella-Spearbit-Security-Review-October-2024.pdf](https://github.com/spearbit/portfolio/blob/master/pdfs/Sorella-Spearbit-Security-Review-October-2024.pdf)）——是本次调研中少数有正经审计报告的 hook 之一。

**Owner 权限**（推测，可由源码验证）：
- 修改 Solver 集合
- 修改拍卖参数（最小 bid、出价窗口）
- 修改 fee 收钱地址

### 时序图

**Trader 提交订单（拍卖流程）**：

```
Trader
   │  构造 EIP-712 订单（tokenIn/Out/amountIn/minOut/deadline）
   │  提交到 Angstrom 入口
   ▼
Angstrom 入口合约
   │  广播给 Solver 网络
   ▼
Solver 网络
   │  1. 内部撮合：能直接匹配的订单对消掉
   │  2. 剩余订单 → 打包成"batch"
   │  3. Solver 对整个 batch 出价（bid = LP 加成）
   ▼
获胜 Solver
   │  用 EIP-712 签出 batch
   ▼
Relayer（bundler）
   │  调用 poolManager.swap(key, params)
   │     params.data = abi.encode(AngstromSwapData{batch, solverSignature})
   ▼
PoolManager.unlock ──► hook.beforeSwap(sender, key, params)
                          │
                          ├─ 解码 params.data → 校验 Solver 签名
                          ├─ 校验：未过 deadline / 未被重放
                          ├─ 把 batch 内部成交的部分直接 settle（不走 v4 路径）
                          ├─ 把剩余订单送入 v4 集中度 swap
                          └─ return (selector, delta=0)
   │
   ▼
PoolManager 执行 v4 集中度 swap（fee 已被动态调节）
   │
   ▼
hook.afterSwapReturnsDelta
   │  把"Solver bid - LP base fee"差额 mint 给 LP（or hook 账本）
```

**LP 加流动性**：

```
LP
   │  poolManager.modifyLiquidity(key, params)
   ▼
hook.beforeAddLiquidity
   │
   ├─ 校验：当前没有未结算的拍卖 batch
   ├─ 暂停新一轮拍卖（防止 LP 进入瞬间被套利）
   └─ 放行 modifyLiquidity
```

### 风险与限制

1. **`requiresCustomSwapData` 的副作用**：任何想"借道 Angstrom 池做市"的策略机器人必须自己实现 Angstrom 的 calldata 编码——集成成本高。
2. **Solver 中心化风险**：Solver 网络目前由 Sorella 团队运行；如果 Solver 串谋/下线，整个拍卖系统停摆。
3. **拍卖失败兜底**：若一轮拍卖无 Solver 出价，对应 batch 的 swap 必须 revert——trader 体验上可能比普通 v4 池子差。
4. **审计报告完整但代码复杂度高**：Spearbit 报告覆盖到了，但 am-AMM / Solver / hook 三层耦合，单独修改任何一层都需要重新审计。
5. **不可升级假设**：若 hook 是 `upgradeable=False`，Solver 集合 / 拍卖参数调整需要重新部署——v4 hook 没有传统 proxy 升级路径。
6. **gas 成本**：每次 swap 多一次 calldata 解码 + 签名校验，比普通 v4 池子贵 ~30-50k gas。
7. **EIP-712 domain 绑定**：`requiresCustomSwapData` 通常意味着 domain separator 绑定 `chainId` + `verifyingContract`——Angstrom 跨链部署需要重新签名。
8. **Dune 30d 268M 数据基线**：基于 Dune 已标注的 Sorella 标签；该数字包含所有 Angstrom 池子总和，单池量级视部署链而定。
9. **MEV 内部化的边界**：Angstrom internalize 的是"套利 + sandwich"型 MEV——纯粹的 JIT 流动性（add/remove LP）型 MEV 不在拍卖范围内。
10. **普通 trader 视角**：trader 拿到的"低 gas + 低滑点"是有代价的——订单被 Solver 网络筛选，**trader 失去了"被 mempool searcher 服务"的选项**，必须信任 Solver 公平性。

### 设计原理（核心机制实现细节）

把 Angstrom 的 4 个核心机制拆到**数据结构 / 密码学原语 / 价值流 / 状态机**层面，解释每一步是怎么算出来的。

---

#### 1. 应用专属拍卖（App-Specific Auction）

**目的**：把"该批订单按什么价格成交"这个权利拍卖给 Solver——Solver 出价 = 给 LP 的额外 fee 补偿。这是 Angstrom 整套机制的**价值捕获起点**。

**为什么是"应用专属"**：
- 传统 PBS（如 Flashbots）拍卖的是**通用区块空间**：searcher 给 builder 出价，builder 排进区块
- Angstrom 拍卖的是**某一笔 swap batch 的内部路径**：Solver 决定"这 100 笔订单之间能否互相吃掉（无套利）"
- 拍卖标的更窄、出价方更专业 → Solver 能 internalize 的 MEV 比通用 searcher 多

**拍卖对象**（核心数据结构，伪代码）：

```solidity
struct AuctionBatch {
    PoolId poolId;                        // 哪个 v4 池子
    Order[] orders;                       // 该批待成交订单
    address solver;                       // 获胜 Solver
    uint256 solverBidAmount;              // Solver 出价（=LP 加成）
    uint256 deadline;                     // 拍卖窗口截止
    bytes solverSignature;                // Solver EIP-712 签
}
```

**拍卖流程状态机**：

```
        ┌─────────────────┐
        │ 1. 订单收集      │  Trader 提交订单，Angstrom 入口聚合
        │   (off-chain)    │  → 订单排序按接收时间
        └────────┬────────┘
                 │
                 ▼
        ┌─────────────────┐
        │ 2. Solver 竞价   │  链下 Solver 评估：能否 internalize？
        │   (off-chain)    │  ├─ 能：报出最高 internalizeBid
        │                 │  └─ 不能：报出 v4 路径最差价
        └────────┬────────┘
                 │
                 ▼
        ┌─────────────────┐
        │ 3. 获胜 Solver  │  出价最高者胜
        │   (off-chain)    │  → 用 EIP-712 签 batch
        └────────┬────────┘
                 │
                 ▼
        ┌─────────────────┐
        │ 4. 上链执行      │  Relayer 提交：poolManager.swap(key, params)
        │   (on-chain)     │  params.data = abi.encode(batch, signature)
        │                 │  hook 解码 → 校验签名 → 执行
        └─────────────────┘
```

**Solver 收益来源**（关键算式）：

```
SolverProfit = (订单 internalize 的总价值 + LP 实际到手) - (Solver 支付给 LP 的 bid) - (v4 路径净成本)
```

- 如果 Solver 能把 50% 订单 internalize，则少走 50% v4 路径，节省 LVR
- Solver 愿意把节省的一部分以 **bid** 形式支付给 LP
- LP 拿到 base fee + Solver bid，**LP 总收益 > 普通 v4 池子**
- 这是 Angstrom 跑出 $268M 量级的根本原因

**失败兜底**：
- 如果一轮拍卖**无 Solver 出价**：整个 batch 的 swap 必须 revert（trader 体验下降但保护机制完整）
- 这是与 BunniHook 最大的不同——**BunniHook 有 am-AMM 失败 burn 模式，Angstrom 是直接 revert**

---

#### 2. `requiresCustomSwapData` + EIP-712 校验

**目的**：用密码学锁强制"所有 swap 必须经过 Solver 拍卖"——这是 Angstrom 独占排序权的物理基础。

**`requiresCustomSwapData` 是什么**：
- v4 PoolManager 提供的 hook 标志位
- 设置后，`PoolManager.swap` 的 `params.data` 字段**必须**携带 hook 自定义 calldata，否则 revert
- 等于："你不能直接调 swap，必须先得到 hook 的同意"

**校验逻辑**（`hook.beforeSwap` 内，伪代码）：

```solidity
function beforeSwap(sender, key, params) external returns (bytes4, BeforeSwapDelta, uint24) {
    // 1. 解码 params.data
    (AuctionBatch memory batch, bytes memory sig) = abi.decode(params.data, (AuctionBatch, bytes));

    // 2. 校验：池子匹配
    require(batch.poolId == key.toId(), "wrong pool");

    // 3. EIP-712 签名校验
    bytes32 structHash = keccak256(abi.encode(
        BATCH_TYPEHASH,
        batch.poolId,
        batch.orders,
        batch.solver,
        batch.solverBidAmount,
        batch.deadline
    ));
    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    address recovered = ecrecover(digest, sig.v, sig.r, sig.s);
    require(recovered == batch.solver, "bad solver sig");

    // 4. 重放保护
    require(block.timestamp <= batch.deadline, "expired");
    require(!s.consumedBatchHash[keccak256(abi.encode(batch))], "replay");

    // 5. 标记为已消费
    s.consumedBatchHash[keccak256(abi.encode(batch))] = true;

    // ... 继续执行 v4 swap
    return (this.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
}
```

**EIP-712 Domain Separator**：

```solidity
bytes32 DOMAIN_SEPARATOR = keccak256(abi.encode(
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
    keccak256(bytes("Angstrom")),
    keccak256(bytes("1")),
    block.chainid,
    address(this)  // verifyingContract = hook 地址
));
```

**为什么是"密码学锁"而不是"管理员白名单"**：
- 管理员白名单：Owner 可临时关停 = 单点
- 密码学锁：只有 Solver 能签 = 排序权**结构上**属于 Solver 网络
- 即使 Angstrom 团队自己也无法伪造 Solver 签名（除非攻破 Solver 私钥）

**重放保护关键**：
- `s.consumedBatchHash[batchHash]` 一旦置 true，**同 batchHash 不能再用**
- 即使 attacker 拿到 Solver 签，也无法在第二个区块重放

---

#### 3. 订单内部撮合（Order Internal Matching）

**目的**：在 Solver 阶段就把能匹配的订单直接对消掉，**不走 v4 路径**——这是 MEV 内部化的核心。

**匹配逻辑**（链下 Solver 内部代码，伪代码）：

```python
def internalize(orders: List[Order]) -> MatchResult:
    # 1. 按 token pair 分桶
    buckets = defaultdict(list)
    for o in orders:
        buckets[(o.tokenIn, o.tokenOut)].append(o)

    matched = []
    unmatched = []

    for (tIn, tOut), bucket in buckets.items():
        # 2. 按价格优先 + 时间次之排序
        bucket.sort(key=lambda o: (-o.priceLimit, o.submittedAt))

        # 3. 贪心撮合：买价最高的卖单 vs 卖价最低的买单
        buy_heap = []   # max-heap by price
        sell_heap = []  # min-heap by price
        for o in bucket:
            if o.isBuy:
                heappush(buy_heap, (-o.priceLimit, o))
            else:
                heappush(sell_heap, (o.priceLimit, o))

        while buy_heap and sell_heap:
            best_buy = buy_heap[0][1]
            best_sell = sell_heap[0][1]
            if -best_buy.priceLimit >= best_sell.priceLimit:  # 价差 >= 0
                fillAmount = min(best_buy.amount, best_sell.amount)
                matched.append(Match(best_buy, best_sell, fillAmount))
                # 更新剩余 amount，可能部分成交
                # ...
            else:
                break  # 无套利空间

        # 未撮合的订单进 v4 路径
        unmatched.extend(remaining_orders)

    return MatchResult(matched=matched, unmatched=unmatched)
```

**链上 settle**（`beforeSwap` 中）：

```solidity
// matched 部分：直接 transferFrom trader <-> trader，不走 v4
for (Match memory m : batch.matched) {
    IERC20(m.tokenIn).transferFrom(m.buyer, m.seller, m.fillAmount);
    IERC20(m.tokenOut).transferFrom(m.seller, m.buyer, m.fillAmount);
}

// unmatched 部分：送入 v4 集中度 swap
// （剩余 amount 直接走 v4.standardSwap）
```

**价值流对比**：

| 路径 | 普通 v4 | Angstrom 内部撮合 |
|---|---|---|
| 撮合 | 全部走 v4 集中度曲线 | 同 pair 订单直接对消 |
| LVR | 100% 暴露给套利者 | 价差被 Solver 内部吃掉，**不给套利者** |
| LP 收益 | LP fee | LP fee + Solver bid |
| Trader 滑点 | 集中度曲线滑点 | 0 滑点（内部撮合部分） |

**为什么是"应用专属"的关键**：
- 通用 PBS（如 Flashbots）做不到这一点——它只决定"哪个 tx 排前面"，不知道"两个 tx 之间能否套利"
- Angstrom 拍卖让 Solver 有**看完整 batch 的能力** + **commit 整批的能力**，才能 internalize

---

#### 4. MEV 内部化 + `afterSwapReturnsDelta`

**目的**：把 Solver 在拍卖中省下的 LVR / sandwich 利润，**结构性地**回流给 LP 和 trader，而不是被外部 searcher 抢走。

**`afterSwapReturnsDelta` 是什么**：
- v4 PoolManager 提供的 hook 标志位
- 设置后，`hook.afterSwap` 可以返回一个 `BeforeSwapDelta`（注意名字是历史遗留）
- 这个 delta 会被 v4 加到 swap 的输入侧，**等于在 swap 之外推一笔资金进 PM 账本**

**delta 推送逻辑**（`hook.afterSwap` 中，伪代码）：

```solidity
function afterSwap(sender, key, params, delta, amount) external
    returns (bytes4, int128)
{
    int128 hookDelta = 0;

    // 1. 累加 Solver bid
    uint256 solverBid = batch.solverBidAmount;

    // 2. 减去 LP base fee（已经在 swap 路径中扣除）
    uint256 lpBaseFee = ...;  // 从 swap 计算中获取

    // 3. 剩余 = 归 LP 的"额外 LP 加成"
    int128 extraToLP = int128(int256(solverBid - lpBaseFee));

    if (extraToLP > 0) {
        // 4. 把这笔钱 mint 到 PM 账本
        poolManager.mint(lpRecipient, Currency.unwrap(batch.tokenIn), uint256(extraToLP));
        hookDelta = int128(int256(solverBid));
    } else {
        // 异常：Solver bid < LP base fee → 等于 LP 亏了
        // 这种 batch 应该 revert，但留个降级路径
        hookDelta = 0;
    }

    return (this.afterSwap.selector, hookDelta);
}
```

**`afterDonate` 的辅助作用**：
- 协议可主动调用 `poolManager.donate(poolKey, amount0, amount1, ...)`
- 把协议金库 / 拍卖罚金的 token 直接捐给池子
- 相当于给所有 LP **额外分红**（与 swap fee 累加）

**MEV 内化的边界**（关键认知）：

| MEV 类型 | 走 v4 普通路径 | Angstrom 内部化 |
|---|---|---|
| **跨池套利**（与外部 CEX/DEX 价差） | 套利者赚 | Solver internalize |
| **Sandwich**（前后夹击） | 套利者赚 | 被拒绝（订单进 batch 后无法 front-run） |
| **JIT 流动性**（add/remove LP） | 套利者赚 | **不在拍卖范围**——仍可能被外部 searcher 套利 |
| **清算 MEV**（借贷协议衍生） | 套利者赚 | 不在 Angstrom 范围 |

最后这一行是 Angstrom 的**已知盲点**：JIT 流动性 MEV 仍然外流。Sorella 团队曾讨论过把 JIT 也纳入拍卖，但会增加 LP 进入/退出的延迟。

---

#### 四机制的协同关系

```
                 ┌─────────────────────┐
                 │  Trader 提交订单    │
                 └──────────┬──────────┘
                            │
                            ▼
                 ┌─────────────────────┐
                 │  1. Solver 拍卖     │ ← 链下 Solver 网络竞价
                 │   (出价最高者胜)    │
                 └──────────┬──────────┘
                            │
                            ▼
                 ┌─────────────────────┐
                 │  2. 内部撮合        │ ← Solver 看完整 batch
                 │   (matched 部分)    │   matched 直接 transferFrom
                 └──────────┬──────────┘
                            │
                            ▼
                 ┌─────────────────────┐
                 │  3. EIP-712 校验    │ ← hook 强制要求 Solver 签
                 │   (unmatched 部分)  │   普通 swap 被拒绝
                 └──────────┬──────────┘
                            │
                            ▼
                 ┌─────────────────────┐
                 │  4. v4 swap         │ ← unmatched 走集中度曲线
                 │   + afterSwapDelta  │   Solver bid 推回 PM 账本
                 └──────────┬──────────┘
                            │
                            ▼
                 ┌─────────────────────┐
                 │  LP 收益：          │
                 │  base fee + bid     │ ← 结构上 > 普通 v4 池
                 └─────────────────────┘
```

四个机制是**同一笔 batch 的不同阶段**：
- **拍卖** = 价值定价
- **撮合** = 路径优化
- **EIP-712** = 访问控制
- **`afterSwapDelta`** = 价值回流

LP 由此从"被动承受 LVR"变成"主动拍卖 LVR 回收权"——这是 Angstrom 被称为"v4 hook 体系最具颠覆性设计"的原因。

---

#### 与 BunniHook 的对比

| 维度 | BunniHook | Angstrom |
|---|---|---|
| MEV 捕获方式 | am-AMM 拍卖 swap 流 | Solver 拍卖 batch 内部路径 |
| 拍卖对象 | "未来 N 笔 swap 的 fee" | "该 batch 的最优成交路径" |
| 拍卖地点 | 链上（am-AMM manager） | 链下（Solver 网络） |
| 价格决定 | 链上 bonding curve | 链下自由出价 |
| 失败模式 | 出价者 BunniToken 被 burn | 整批 revert |
| LP 加成来源 | am-AMM manager 预付 bid | Solver 把节省的 LVR 折现为 bid |
| JIT 抗性 | 弱（am-AMM 不管 LP 进出） | 弱（同 BunniHook） |
| Sandwich 抗性 | 中（surge fee 抬价） | **强**（requiresCustomSwapData 阻断 mempool 截胡） |
| 跨池套利抗性 | 弱（pool 内 surge fee） | **强**（Solver internalize 跨池套利） |

**Ring 借鉴建议**（与 summary.md 对齐）：
- 如果要"照搬 BunniHook"：抄 surge fee + am-AMM（适合 fewToken 1:1 wrap 池）
- 如果要"照搬 Angstrom"：需要先建 Solver 网络，**运营成本远超 wrap 类业务**——summary.md 第三节也明确不建议学
