# LivoSwapHook 详细调研

> **地址**: [0x627fa6f76fa96b10bae1b6fba280a3c9264500cc](https://etherscan.io/address/0x627fa6f76fa96b10bae1b6fba280a3c9264500cc)
> **部署方**: `0xBa489180Ea6EEB25cA65f123a46F3115F388f181` (LivoLaunchpad)
> **审计报告**: [Livo Labs Collaborative Audit 2026.01.29](https://github.com/LivoLaunchpad/livo-contracts/blob/main/audits/2026.01.29%20-%20Final%20-%20Livo%20Labs%20Collaborative%20Audit%20Report%201769696282.pdf)
> **源码**: [`/Users/alexla/code/uniswap/hooklist/.sources/0x627fa6f76fa96b10bae1b6fba280a3c9264500cc/src_hooks_LivoSwapHook.sol`](file:///Users/alexla/code/uniswap/hooklist/.sources/0x627fa6f76fa96b10bae1b6fba280a3c9264500cc/src_hooks_LivoSwapHook.sol)

## 1. Hook 概述

LivoSwapHook 是 Livo Launchpad 项目在 Uniswap V4 上的核心 hook。它的作用是：
- 拦截 `已毕业 (graduated)` 的 Livo Token 池子的每一笔 swap
- 对 swap 抽取两种费用：
  - **LP 手续费**：固定 1% (`LP_FEE_BPS = 100`)
  - **买卖税**：从 token 的 `TaxConfig` 动态读取，时间段内有效
- 它是一个**单例 (singleton) hook**，即同一个 hook 合约服务 Livo 平台所有已毕业 token 池子
- 只能在 token 毕业后才能开池交易，毕业前 swap 会被 `revert("NoSwapsBeforeGraduation")`

**项目方**：[LivoLaunchpad](https://github.com/LivoLaunchpad) —— 一个 memecoin/社区代币发行平台。

## 2. 收益结构

### 2.1 收入来源

LivoSwapHook 抽取两种费用，全部用 ETH (Currency0) 计价：

| 费用类型 | 费率 | 计费基数 | 何时收取 |
|---|---|---|---|
| LP 手续费 (LP Fee) | **1%** (固定 100 bps) | 买入时 = ETH 输入额；卖出时 = ETH 输出额 | 每笔 swap |
| 买入税 (Buy Tax) | 动态 (`buyTaxBps`) | 买入时 ETH 输入额 | 仅在 `tax period` 内 |
| 卖出税 (Sell Tax) | 动态 (`sellTaxBps`) | 卖出时 ETH 输出额 | 仅在 `tax period` 内 |

> `tax period` 的判定：`block.timestamp <= graduationTimestamp + taxDurationSeconds`

### 2.2 收益分配

**LP 手续费 1%** 拆分：
- **50% 给 Token 创作者 (Creator)**
- **50% 给协议金库 (Treasury)**
  - Treasury 地址来自 `ILivoLaunchpad(LAUNCHPAD).treasury()`

**买卖税 (Buy/Sell Tax)**：
- **100% 归 Token 创作者 (Creator)**

### 2.3 收益收取方式

LivoSwapHook 使用 Uniswap V4 的 `poolManager.take()` 机制直接从池子提取 ETH：
- **买入**：在 `beforeSwap` 阶段按 `ethIn × (LP_FEE_BPS + buyTaxBps) / 10000` 提前 take
- **卖出**：在 `afterSwap` 阶段按 `ethOut × (LP_FEE_BPS + sellTaxBps) / 10000` take（因为卖出时 ETH 输出额要等 swap 完成后才知道）

提取后通过 `ILivoToken(tokenAddress).accrueFees{value: ...}()` 统一记账到 token，treasury 部分用 `treasury.call{value: ...}("")` 直接转账。

### 2.4 收益特征

- **时间窗口式税收**：买卖税只在 `graduationTimestamp + taxDurationSeconds` 之内收取，过期后只收 1% LP 费
- **不对称税率**：买入税和卖出税可以不一样（典型配置：卖税高于买税以抑制砸盘）
- **稳态费率**：税收过期后，实际费率固定为 1% LP 费（与 Uniswap v4 标准池的 0.3% 相比仍然偏高）

## 3. 工作原理

### 3.1 关键参数

```solidity
uint256 private constant BASIS_POINTS = 10000;
uint256 private constant LP_FEE_BPS = 100;          // 1% LP 费
uint256 private transient _cachedBuyFee;             // beforeSwap → afterSwap 之间缓存
address public immutable LAUNCHPAD;                  // 用于解析 treasury
```

### 3.2 关键权限位

`getHookPermissions()` 返回：
- `beforeSwap: true`
- `afterSwap: true`
- `beforeSwapReturnDelta: true`（买入时直接从池子 take ETH）
- `afterSwapReturnDelta: true`（卖出时从池子 take ETH）

注意 hook 地址本身需要通过 CREATE2 部署，使得地址的特定 bit 位匹配这些权限位（Uniswap v4 的标准做法）。

### 3.3 买入流程 (zeroForOne = true)

```
在 beforeSwap 阶段：
1. 解析 token = currency1
2. 校验 token.graduated() == true，否则 revert NoSwapsBeforeGraduation
3. 计算：
   - lpFee     = ethIn × 1%
   - taxAmount = (graduation period 内 ? ethIn × buyTaxBps : 0)
   - totalFee  = lpFee + taxAmount
4. 缓存 totalFee 到 transient _cachedBuyFee
5. poolManager.take(currency0, address(this), totalFee)  ← 直接从池子抽走 ETH
6. _accrue(token, lpFee, taxAmount)：
   - 创作者部分 (LP 50% + tax 100%) → ILivoToken.accrueFees{value: ...}
   - treasury 50% LP → treasury.call{value: ...}
7. 返回 BeforeSwapDelta = (totalFee, 0)，让 PoolManager 调整实际输入

在 afterSwap 阶段：
- emit LivoSwapBuy(token, tx.origin, ethIn, tokensOut, _cachedBuyFee)
- 返回 (selector, 0)，不再二次抽费
```

### 3.4 卖出流程 (zeroForOne = false)

```
在 beforeSwap 阶段：
- 仅检查 graduation，不抽费（因为卖出时不知道 ETH 输出额）
- 返回 ZERO_DELTA，0 费率

在 afterSwap 阶段：
1. 解析 token = currency1
2. 计算：
   - absEthAmount = uint128(delta.amount0())   ← 实际 ETH 输出
   - lpFee        = absEthAmount × 1%
   - taxAmount    = (graduation period 内 ? absEthAmount × sellTaxBps : 0)
   - totalFee     = lpFee + taxAmount
3. poolManager.take(currency0, address(this), totalFee)
4. _accrue(token, lpFee, taxAmount)  ← 同买入
5. emit LivoSwapSell(token, tx.origin, tokensIn, absEthAmount, totalFee)
6. 返回 int128(totalFee)
```

### 3.5 关键依赖

- `ILivoToken`: 提供 `graduated()`, `getTaxConfig()`, `accrueFees()`
- `ILivoLaunchpad`: 提供 `treasury()` 解析
- `BaseHook`: Uniswap v4 标准 hook 抽象

## 4. 时序图 (Sequence Diagram)

### 4.1 买入时序 (Buy, ETH → Token)

```
User           PoolManager        LivoSwapHook       LivoToken       Launchpad      Treasury
 |                  |                   |                |                |              |
 |--swap(currency0=ETH, amount=100)--->|                |                |              |
 |                  |                   |                |                |              |
 |                  |--beforeSwap()---->|                |                |              |
 |                  |                   |--graduated?--->|                |              |
 |                  |                   |<--true---------|                |              |
 |                  |                   |                |                |              |
 |                  |                   |--getTaxConfig()--------------->|              |
 |                  |                   |<--buyTaxBps, sellTaxBps, taxDuration---|
 |                  |                   |                |                |              |
 |                  |                   |  (lpFee=1.0, tax=0.5 → totalFee=1.5)       |
 |                  |                   |--take(currency0, self, 1.5)---->|              |
 |                  |                   |<--ok-----------|                |              |
 |                  |                   |                |                |              |
 |                  |                   |--accrueFees{value:1.25}()----->|              |
 |                  |                   |                | (creator LP 0.5 + tax 0.75)    |
 |                  |                   |                |                |              |
 |                  |                   |--treasury()------------------->|              |
 |                  |                   |<--treasuryAddr----------------|              |
 |                  |                   |                |                |              |
 |                  |                   |--call{value:0.5}------------------------------>|
 |                  |                   |                |                |              |
 |                  |                   |  (return BeforeSwapDelta(1.5, 0))             |
 |                  |<--selector, delta, feeOverride------|                |              |
 |                  |                   |                |                |              |
 |                  | (执行 swap，按调整后的 amount 走 v4 撮合)             |              |
 |                  |                   |                |                |              |
 |                  |--afterSwap()----->|                |                |              |
 |                  |                   |--emit LivoSwapBuy(token, user, 100, tokensOut, 1.5)--
 |                  |<--selector, 0-----|                |                |              |
 |<--BalanceDelta---|                   |                |                |              |
```

### 4.2 卖出时序 (Sell, Token → ETH)

```
User           PoolManager        LivoSwapHook       LivoToken       Launchpad      Treasury
 |                  |                   |                |                |              |
 |--swap(currency0=ETH, amount=-50)---->|                |                |              |
 |                  |                   |                |                |              |
 |                  |--beforeSwap()---->|                |                |              |
 |                  |                   |--graduated?--->|                |              |
 |                  |                   |<--true---------|                |              |
 |                  |                   |                |                |              |
 |                  |                   | (return ZERO_DELTA，sell 在 afterSwap 抽费) |
 |                  |<--selector, 0, 0--|                |                |              |
 |                  |                   |                |                |              |
 |                  | (执行 swap)       |                |                |              |
 |                  |                   |                |                |              |
 |                  |--afterSwap(delta, amount0=+95)---->|                |              |
 |                  |                   |--getTaxConfig()--------------->|              |
 |                  |                   |<--sellTaxBps---|                |              |
 |                  |                   |                |                |              |
 |                  |                   |  lpFee=0.95, tax=1.9 → total=2.85            |
 |                  |                   |--take(currency0, self, 2.85)---->|              |
 |                  |                   |                |                |              |
 |                  |                   |--accrueFees{value:2.375}()---->|              |
 |                  |                   |                | (creator LP 0.475 + tax 1.9)  |
 |                  |                   |                |                |              |
 |                  |                   |--treasury()------------------->|              |
 |                  |                   |--call{value:0.475}--------------------------->|
 |                  |                   |                |                |              |
 |                  |                   |--emit LivoSwapSell(token, user, 50, 95, 2.85)-|
 |                  |<--selector, 2.85--|                |                |              |
 |<--BalanceDelta---|                   |                |                |              |
```

### 4.3 关键时间点说明

| 时间点 | 事件 | 行为 |
|---|---|---|
| Token 毕业前 | 用户调用 swap | `revert NoSwapsBeforeGraduation` |
| Token 毕业后 | 买入 (Buy) | `beforeSwap` 直接从池子 take ETH，分配给 creator/treasury |
| Token 毕业后 | 卖出 (Sell) | `afterSwap` 从池子 take ETH，分配给 creator/treasury |
| 税收期结束 | 任意 swap | `shouldTax = false`，只收 1% LP 费 |
| 税收期结束 | 任意 swap | 完全不调用 `_getTaxParams` 的税计算分支（短路判断 `taxDurationSeconds` 过期） |

## 5. 风险与限制

### 5.1 ETH 卡死风险
源码注释明确指出：
> "ETH should never remain in this contract between transactions. If it does, it is accepted as stuck. Adding a rescue mechanism would require `Ownable`, which is avoided to keep this singleton hook minimal and ownerless."

如果 `take()` 成功但后续转账失败，ETH 会卡在 hook 合约里。

### 5.2 单点依赖
- 强依赖 `LivoLaunchpad.treasury()`
- 强依赖 `ILivoToken` 的 `graduated()` 状态，token 实现必须可信
- 强依赖 `ILivoToken.accrueFees()`，需要该函数能正常处理 ETH

### 5.3 governance 控制
`swapAccess = governance` 表示 governance 可以配置 `tax` 行为（如调高 sellTaxBps），属于需要信任运营方的设计。

## 6. 总结

LivoSwapHook 是个**典型 launchpad 项目的"税 + LP 费"型 hook**：
- 通过**单例**设计服务所有 token
- 通过**时间窗口**控制税率生效期
- 通过**不对称税率**抑制卖出砸盘
- 收入按 **50/50 LP + 100% tax** 分配给创作者与协议金库

它**不直接抽取 ETH 到 Livo 协议**，而是通过 `accrueFees` 记账到具体的 token 合约，再由 token 合约按其自身逻辑分配（例如给创作者锁仓、线性释放等）。
