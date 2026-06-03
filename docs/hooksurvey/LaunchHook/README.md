# LaunchHook

> **地址**: [0x8bd422134164f74023308a22ba991ae0412900cc](https://etherscan.io/address/0x8bd422134164f74023308a22ba991ae0412900cc)
> **链**: Ethereum (chainId=1)
> **部署方**: `0x9155F76A8349129abd66406cBbBC7D286E5bb031`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | LaunchHook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeSwap`, `afterSwap`, `beforeSwapReturnsDelta`, `afterSwapReturnsDelta`

## 属性

`swapAccess=none`

## 功能描述

LaunchHook is the fee-collection hook used by the Tickr launchpad. It charges a flat 2% fee on every swap (taken from input ETH on buys via beforeSwap and from output ETH on sells via afterSwap) and splits it 50/50 between the token's creator — the holder of the corresponding TickrOwner NFT — and the platform. Fee constants and the creator/platform split are immutable; the only governor action is a one-time setFactory(...) binding.

## 调研结果

### 收益结构

| 项 | 值 | 备注 |
|---|---|---|
| 总费率 | 2% (`FEE_BPS = 200`) | 不可改的 `constant` |
| 创作者分成 | 50% (`CREATOR_SHARE_BPS = 5000`) | 进入 Token 合约，由其 `withdrawFees()` 流到 `TickrOwner NFT` 当前持有者 |
| 平台分成 | 50% | 直接发往 `factory` 合约 |
| LP fee override | 0（未修改） | `_beforeSwap` 返回的第三参数恒为 `0`，Uniswap 走 `key.fee` |
| Protocol fee | 0（未修改） | 不调用 `updateDynamicLPFee`，也不取 `protocolFee` |
| 计费币种 | 仅 ETH (currency0) | 买单从输入 ETH 抽；卖单从输出 ETH 抽 |
| 计费路径 | `poolManager.take(currency, this, fee)` | ETH 通过合约 `receive()` 落地 |

整个机制属于"在 hook 边界外抽成"——LPs 收到的 LP fee 仍按 pool 的 `key.fee` 走，额外的 2% 是从交易者端扣除的税。对交易者来说一笔名义费率 = `LP fee + 2%`（LP fee 默认由 pool 初始化时确定，文档未披露）。constant 化意味着 fee 政策不能通过治理调整；只有 `setFactory()` 是一次性 governor 动作，用于解决"factory 与 hook 互引用的部署死锁"。

### 工作原理

**核心思想**：在 ETH/Token pool 上以 0x8bd4...00cc 形式预计算部署地址（CREATE2 匹配 hooks 地址位），每个 token 一个独立 hook 实例。

**关键代码路径**（`project/contracts/launchHook.sol`）：

```solidity
uint256 public constant FEE_BPS = 200;          // 2.00%
uint256 public constant CREATOR_SHARE_BPS = 5000; // 50% / 50%
```

- **买 (ETH→Token, `zeroForOne=true`, exact-input)**：在 `_beforeSwap` 中按 `amountIn * 2%` 计算 fee → `poolManager.take(currency0, this, feeAmount)` 将 ETH 从 PoolManager 拉出 → `_distribute` 切分 → 返回 `BeforeSwapDelta(-feeAmount, 0)`，告诉 PoolManager 把 feeAmount 从 input 端扣掉。
- **卖 (Token→ETH, `zeroForOne=false`, exact-input)**：在 `_afterSwap` 中拿到 `delta.amount0()`（输出 ETH），按 `ethOut * 2%` 计算 fee → `poolManager.take` 拉出 → `_distribute` 切分 → 返回 `int128(feeAmount)` 让 PoolManager 从 output 端扣掉。
- **分发 (`_distribute`)**：
  - `creatorAmount` → `payable(tokenAddress).call{value: ...}("")`，由 token 合约记账
  - `platformAmount` → `payable(factory).call{value: ...}("")`
  - emit `FeeCollected(token, totalFee, creatorShare, platformShare)`
- **不支持路径**（直接绕过、不收 fee）：
  - `zeroForOne=true` 且 `amountSpecified >= 0`（即 exact-output 买）→ `_beforeSwap` 直接返回 zero delta
  - `zeroForOne=false` 且 `amountSpecified >= 0`（即 exact-output 卖）→ `_afterSwap` 直接返回 0
  - 这意味着 exact-output 交易可以零成本穿过 hook——这是合约层的"逃生口"，可能成为博弈空间

**factory ↔ hook 绑定**：factory 部署 hook 之后，调用 `setFactory(factory)` 一次性绑定，且 `require(factory == address(0))` 保证不可重绑。

**ETH 接收**：合约通过 `receive() external payable {}` 接收 `poolManager.take` 推过来的 native ETH。

### 时序图

**Buy 路径** (ETH → Token, exact-input, zeroForOne=true):
```
User/UniversalRouter
   │  swap(PoolKey, SwapParams{zeroForOne=true, amountSpecified=-amountIn})
   ▼
PoolManager.unlock ──► hook.beforeSwap
                          │
                          ├─ amountIn = -amountSpecified
                          ├─ fee = amountIn * 200 / 10000
                          ├─ poolManager.take(currency0, this, fee)   // 拉 ETH
                          ├─ _distribute(key, fee):
                          │     ├─ token.call{value: creatorShare}("")
                          │     └─ factory.call{value: platformShare}("")
                          └─ return (selector, toBeforeSwapDelta(-fee, 0), 0)
                              ▲
                              │   PoolManager 据此把 fee 从 input 端扣掉
PoolManager 执行集中度 swap（输入端已减 fee）
   │
   ▼
Swap 完成（fee 已结算，输出 token 给 user）
```

**Sell 路径** (Token → ETH, exact-input, zeroForOne=false):
```
User/UniversalRouter
   │  swap(PoolKey, SwapParams{zeroForOne=false, amountSpecified=-amountIn})
   ▼
PoolManager 执行集中度 swap（无 fee 拦截）
   │
   ▼
PoolManager.unlock ──► hook.afterSwap(delta)
                          │
                          ├─ ethOut = delta.amount0()
                          ├─ fee = ethOut * 200 / 10000
                          ├─ poolManager.take(currency0, this, fee)
                          ├─ _distribute(key, fee)
                          └─ return (selector, int128(fee))
                              ▲
                              │   PoolManager 据此把 fee 从 output 端扣掉
Swap 完成（user 收到 ethOut - fee，creator/platform 已收）
```

### 风险与限制

1. **Exact-output 绕过**：合约层在 `amountSpecified >= 0` 时直接返回 zero delta，**不收 fee**。理论上可被 MEV 套利者用 exact-output 路径规避 2%——需结合 `key.fee` 的实际值评估套利空间。
2. **ETH-only 计费**：只能从 ETH 端抽 fee。如果项目方想用 token 计费或动态调整币种，需重新部署 hook。
3. **不可升级**：`setFactory()` 一次性，fee 常量不可改。如果需要调节费率（如 1% → 0.5%），必须重新部署并迁移 LP。
4. **依赖 token 合约的 `withdrawFees`**：creator share 进入 token 合约后，需 token 合约主动调用 `withdrawFees()` 把 ETH 转给 `TickrOwner NFT` 当前 holder。若 token 合约有 bug / 自毁 / 把 ETH 锁死，creator share 永久 stuck。
5. **revert 风险**：`payable(tokenAddress).call{value: creatorAmount}("")` 失败会整体 revert 单笔 swap。若 token 合约因 EIP-6780 升级后不再 payable，creator 端会让所有买单 revert。
6. **平台 fee 在 `factory == address(0)` 时跳过**（`if (platformAmount > 0 && factory != address(0))`）：如果 governor 还没 `setFactory`，前几笔 swap 的平台 share 会丢失。
7. **单池单 hook**：每个 token 单独部署一个 hook 地址，运营开销大（地址预计算、CREATE2 部署），且 30d 交易量为 0、N/A stats——目前未观察到生产使用或被列入 Tickr 实际 launchpad 主流。
8. **无 LP fee override 策略**：动态费率、波动率调节都不在 hook 能力范围；如果 Uniswap v4 引入 protocol fee 接管输出端，需注意 hook 的 `afterSwap` delta 与 protocol fee 共享 output 时的优先级。
9. **无 reentrancy guard**：依赖 `BaseHook` 的 `noDelegateCall` 间接防护，但 `poolManager.take` 与外部 `call{value:}` 都是外部调用，需在极端市场条件下人工审计重入路径。
10. **审计缺失**：json 元数据 `auditUrl: ""`，部署方单一 EOA，无第三方安全报告。
