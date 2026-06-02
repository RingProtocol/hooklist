# VirtualLBPStrategyBasic 详细调研

> **地址**: [0xd53006d1e3110fd319a79aeec4c527a0d265e080](https://etherscan.io/address/0xd53006d1e3110fd319a79aeec4c527a0d265e080)
> **部署方**: 未公开 (deployer = "")
> **审计报告**: 无
> **源码**: [`/Users/alexla/code/uniswap/hooklist/.sources/0xd53006d1e3110fd319a79aeec4c527a0d265e080/src_distributionContracts_VirtualLBPStrategyBasic.sol`](file:///Users/alexla/code/uniswap/hooklist/.sources/0xd53006d1e3110fd319a79aeec4c527a0d265e080/src_distributionContracts_VirtualLBPStrategyBasic.sol)
> **Dune label**: "Aztec CCA"

## 1. Hook 概述

VirtualLBPStrategyBasic 是 **Aztec** 团队（推测为 Aztec Network 的连续清算拍卖 ContinuousClearingAuction 体系）在 Uniswap V4 上的发行策略 hook。它的作用是：

- 配合 [ContinuousClearingAuction](../) 实现"**虚拟 LBP**"（Liquidity Bootstrapping Pool）
- 池子中流通的是 `IVirtualERC20` —— 一类包装底层代币的"虚拟 ERC20"
- 限制 pool **只能由合约自身初始化**（governance 控制）
- 限制所有 swap **必须在 governance 批准迁移（migrate）后才能执行**
- "Virtual" 的含义：在池子里使用 `VirtualERC20` 而非真实代币；`getPoolToken()` 始终返回**底层代币**地址，用于迁移到 v4 真实池

**关键特征**：
- `vanillaSwap: true` —— swap 行为与普通 v4 池完全一致，不收任何额外费用
- `swapAccess: governance` —— 必须由 governance 显式批准后才能 swap
- 不修改费率、不收税、不返回 delta

## 2. 收益结构

### 2.1 收入来源

**VirtualLBPStrategyBasic 不抽取任何费用**：
- `beforeSwap` 仅做"是否允许 swap"的开关检查，返回 `ZERO_DELTA`
- `afterSwap` 不重写（继承自 `LBPStrategyBasic`，未涉及费用）
- 它本身不直接产生协议收入

### 2.2 间接收益

收益主要来自上层 **[ContinuousClearingAuction](../)** 体系（属于 Aztec CCA），该体系使用一个动态 LBP 曲线对底层代币进行拍卖分发：
- 拍卖方（项目方/创作者）将代币卖给竞拍者，募集 ETH/USDC 等
- 拍卖结束后，调用 `approveMigration()` 开启 swap，并通过迁移机制把流动性搬到 v4
- "Virtual"机制让拍卖在合约内完成，避免直接占用真实代币

**协议方（Aztec）** 的收益：
- 通常来自：**部署服务费 / 拍卖抽成 / 迁移 gas 补贴**
- 取决于上层 `LBPStrategyBasic` 的费用结构（本 hook 是其子类）

### 2.3 与 LBP 传统收益模型的对比

| 模型 | 收益来源 | 特点 |
|---|---|---|
| 传统 LBP（如 Balancer LBP） | swap 费率 | 早期需要大量 ETH 启动；token 起始价高，逐步衰减 |
| ContinuousClearingAuction (Aztec) | 拍卖成交价 | 无需初始流动性；按 bid 时间加权决定成交价 |
| VirtualLBP (本 hook) | 与 CCA 联动 | 用 VirtualERC20 在 v4 上提供可视化的"类 LBP"池 |

## 3. 工作原理

### 3.1 继承结构

```
LBPStrategyBasic (基类)  ←── 实现 beforeInitialize、beforeAddLiquidity 等
    ↑
VirtualLBPStrategyBasic  ←── 本 hook，增加 governance 审批逻辑
```

`VirtualLBPStrategyBasic` 仅 override 了 `getHookPermissions()`、`_beforeSwap()`、`getPoolToken()` 和构造函数，其余逻辑（流动性管理、迁移、tick 计算等）继承自 `LBPStrategyBasic`。

### 3.2 关键权限位

```solidity
function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
        beforeInitialize: true,        // 限制只有策略合约本身能初始化池子
        beforeAddLiquidity: false,
        beforeSwap: true,              // 限制 swap 必须 governance 批准迁移后
        beforeSwapReturnDelta: false,  // 不修改金额
        afterSwap: false,
        ...
    });
}
```

注意：
- 没有 `beforeSwapReturnDelta` ⇒ hook **不修改 swap 金额**
- 没有任何费率修改 ⇒ `dynamicFee: false`
- 只在 `beforeSwap` 做"开关式"校验

### 3.3 关键状态

```solidity
address public immutable GOVERNANCE;        // 治理地址
address public immutable UNDERLYING_TOKEN;  // 底层真实 token (v4 迁移后的池子币)
bool public isMigrationApproved = false;   // 迁移批准开关
```

### 3.4 行为详解

#### `beforeInitialize`（来自 LBPStrategyBasic）
- 校验调用者是策略合约本身（即只有策略合约能开池子）
- 这是关键安全门：**普通用户无法部署同名同配置的池子**

#### `beforeSwap`
```solidity
function _beforeSwap(...) internal view override returns (...) {
    if (!isMigrationApproved) revert MigrationNotApproved();
    return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
}
```

- `isMigrationApproved == false` 时：**所有 swap 都被 revert**
- 批准后：**完全不影响 swap 行为**（v4 标准 swap）

#### `approveMigration()`
- 只能由 `GOVERNANCE` 调用
- 调用后 `isMigrationApproved = true` 永久生效
- 这是发行方/治理方在拍卖结束后"开闸"的明确信号

#### `getPoolToken()`
- 始终返回 `UNDERLYING_TOKEN`（真实代币），而不是 `IVirtualERC20` 的包装代币
- 用于迁移时把流动性搬到以真实代币计价的 v4 池

### 3.5 业务流闭环

```
1. 部署 (deployment)
   部署方调用工厂创建 ContinuousClearingAuction (CCA)
   CCA 创建 LBPStrategyBasic → VirtualLBPStrategyBasic (本 hook)
   策略用 IVirtualERC20 部署 v4 池子（currency0=ETH, currency1=VirtualERC20）

2. 拍卖 (auction)
   用户在 CCA 上 bid ETH/Token
   CCA 根据连续清除曲线（continuous clearing curve）计算价格和分配

3. 迁移 (migration)
   拍卖结束 → 治理方/项目方调用 approveMigration()
   hook 解锁 swap

4. 公开交易 (trading)
   任何人都可以在 v4 池上 swap VirtualERC20 ↔ ETH
   swap 走标准的 v4 撮合，hook 只做"已批准"检查

5. 收尾 (graduation)
   在合适的时机，将流动性迁移到以真实代币为 currency 的 v4 池
   （具体时机由策略决定）
```

## 4. 时序图 (Sequence Diagram)

### 4.1 部署 + 拍卖期 (Auction Phase, swap 被禁用)

```
Project       AuctionFactory    ContinuousCCA    LBPStrategy   VirtualLBPStrategy   PoolManager
 |                  |                  |                |                 |                |
 |--createAuction()>|                  |                |                 |                |
 |                  |--deploy()------->|                |                 |                |
 |                  |                  |--createHook()-|                 |                |
 |                  |                  |                |--deploy------->|                |
 |                  |                  |                |<--hookAddr-----|                |
 |                  |                  |                |                 |                |
 |                  |                  |--initialize(virtualToken, hook)--------------------->|
 |                  |                  |                |--beforeInitialize()---------->|     |
 |                  |                  |                |  (校验: msg.sender == self)        |
 |                  |                  |                |  (return selector)                 |
 |                  |                  |                |                 |                |
 |                  |                  |<------------------poolKey----------------------|   |
 |                  |                  |                |                 |                |
 |                  |                  | (拍卖开始，用户 bid)                              |
 |                  |                  |                |                 |                |
 |--User.swap()-----|------------------|------------------------------------------>|   |
 |                  |                  |                |--beforeSwap()-------->|        |   |
 |                  |                  |                |  (isMigrationApproved==false)    |   |
 |                  |                  |                |  revert MigrationNotApproved()    |   |
 |                  |                  |                |                 |<--revert--|     |
```

### 4.2 拍卖结束 + 迁移批准 (Migration Approved)

```
Project/Governance    VirtualLBPStrategy    PoolManager
 |                          |                  |
 |--approveMigration()------>|                  |
 |   (msg.sender == GOVERNANCE)               |
 |   isMigrationApproved = true               |
 |   emit MigrationApproved()                 |
 |<--ok---------------------|                  |
 |                          |                  |
 | (now swap is allowed)    |                  |
```

### 4.3 公开交易期 (Trading Phase, 已批准迁移)

```
User           PoolManager        VirtualLBPStrategy    V4 Pool (VirtualERC20/ETH)
 |                  |                       |                      |
 |--swap(amountX)-->|                       |                      |
 |                  |--beforeSwap()-------->|                      |
 |                  |                       | (isMigrationApproved==true)
 |                  |                       | (return ZERO_DELTA, 0)
 |                  |<--selector, ZERO-----|                      |
 |                  |                       |                      |
 |                  | (执行标准 v4 撮合)     |                      |
 |                  |                       |                      |
 |                  |<--BalanceDelta-------------------------------|
 |                  |                       |                      |
 |                  |  (afterSwap 不重写，行为完全等同 v4 标准)     |
 |                  |                       |                      |
 |<--BalanceDelta---|                       |                      |
```

### 4.4 收尾迁移 (Graduation to Real Pool)

```
Governance/Project   VirtualLBPStrategy   New V4 Pool (UNDERLYING_TOKEN/ETH)
       |                     |                       |
       |--migrateToNewPool()|                       |
       |                     | (创建并初始化新池子，使用 UNDERLYING_TOKEN)
       |                     | (把旧池子的流动性按当前价格搬过去)
       |                     | (旧池子最终可能 burn 或保留作为镜像)
       |<--ok----------------|                       |
```

## 5. 与上层 Auction 的关系

| 组件 | 角色 |
|---|---|
| **ContinuousClearingAuction** | 拍卖核心，按 bid 时间和价格动态分配 token |
| **LBPStrategyBasic** | 拍卖策略基类，负责在 v4 上"模拟 LBP" |
| **VirtualLBPStrategyBasic** | 本 hook，加 governance 批准开关 |
| **IVirtualERC20** | 包装代币，1:1 跟踪真实 token，但不转账真实 token |
| **UNDERLYING_TOKEN** | 真实代币，用于最终迁移 |

**为什么需要 VirtualERC20**：
- 拍卖期间不希望真实代币被转出
- 通过虚拟代币 + hook 控制 swap，能做到"看起来在 LBP，但实际代币没动"
- 拍卖完成、批准迁移后，虚拟池子可用于公开交易
- 最终可选择把流动性迁移到以真实代币为 currency 的标准 v4 池

## 6. 风险与限制

### 6.1 Governance 风险
- `approveMigration()` 是单次单向门（一旦批准不可撤销）
- Governance 地址必须在拍卖真实完成、有合理价格后才批准迁移
- 风险：治理作恶或被攻破 → 强制开闸

### 6.2 swapAccess = governance
- 拍卖期间所有 swap revert
- 这与"普通 v4 池"完全不同的 UX，可能让用户困惑

### 6.3 部署方未公开
- hook 元数据 `deployer = ""`，缺乏透明度
- 缺乏审计报告

### 6.4 复杂依赖链
- 强依赖 `ContinuousClearingAuction` 上层
- 强依赖 `IVirtualERC20` 实现
- 强依赖 `LBPStrategyBasic` 基类逻辑

## 7. 总结

VirtualLBPStrategyBasic 是个**"准入门"式 hook**：
- 它的唯一作用是**控制 swap 的开关**（governance 批准后才能 swap）
- **不抽取任何费用**，不影响 swap 行为
- 配合 `IVirtualERC20` 和 `ContinuousClearingAuction` 实现"虚拟 LBP + 拍卖"
- 是 Aztec CCA 体系在 Uniswap V4 上的**最外层守卫**

它不创造直接收益，而是**保护拍卖机制不被前置交易**，并通过治理方显式批准来保证迁移时机的合理性。
