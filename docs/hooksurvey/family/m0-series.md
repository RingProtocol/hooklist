# M0 Hook 系列合并调研

> **系列定位**: M0 Labs 的访问控制类 hook — 把 Uniswap v4 池子围起来
> **核心机制**: Tick 范围限制 + Allowlist（LP / Swapper / Router / PM）+ Predicate 授权（KYC/身份）
> **覆盖版本**: BaseTickRangeHook（基类）、TickRangeHook（基类特化）、AllowlistHook（基类扩展）

## 1. 概述

M0 Labs 出的两个 hook 都基于 `BaseTickRangeHook`，约束的是"Liquidity Provision"维度：
- **TickRangeHook**（`0xde4005...0800`）：仅约束 LP 的 tick 范围
- **AllowlistHook**（`0xaf53cb...88a0`）：在 TickRangeHook 之上叠加 LP / Swapper / Router / PM 四个 allowlist，加上 Predicate 第三方授权
- 两者都基于同一条业务假设：被监管/合规约束的池子（如稳定币、机构 RWA），只让"白名单"参与者提供流动性或 swap

两者均不可升级（`upgradeable=False`），但**管理权可换**（AccessControl 角色），并且通过 Predicate 接入链上 KYC。

## 2. 覆盖的 Hook 列表

| 子类 | 名称 | 地址 | 权限位 | 30d 交易量 | Swap 数 | Pool |
|---|---|---|---|---|---|---|
| Base | TickRangeHook | [0xde400595199e6dae55a1bcb742b3eb249af00800](https://etherscan.io/address/0xde400595199e6dae55a1bcb742b3eb249af00800) | `beforeAddLiquidity` | $0.00 | N/A | N/A |
| Base+ACL | AllowlistHook | [0xaf53cb78035a8e0acce38441793e2648b15b88a0](https://etherscan.io/address/0xaf53cb78035a8e0acce38441793e2648b15b88a0) | `beforeAddLiquidity, beforeSwap, beforeDonate` | $0.00 | N/A | N/A |

## 3. 收益结构

| 项 | TickRangeHook | AllowlistHook |
|---|---|---|
| LP fee 抽成 | 无 | 无 |
| Protocol fee 抽成 | 无 | 无 |
| Tick 范围管理费 | 0 | 0 |
| 第三方 Predicate 授权 | 关闭 | 启用（KYC 供应商收 fiat 费） |
| **典型商业模式** | 自托管受限池 | 接入合规身份供应商，按 KYC/Business Verification 收 SaaS 费 |

M0 系列不是"抽成型"hook——它本身不收任何交易费，其商业逻辑是让一个"机构池子"能在 Uniswap v4 上运行，由 Allowlist + Predicate 替代传统的 KYC/AML 通道。收益不直接体现在 hook 合约余额，而体现在：(a) hook operator 收企业部署费；(b) Predicate 服务费；(c) 项目方发币侧的 launchpad/服务费。

## 4. 工作原理

### 4.1 `BaseTickRangeHook`（两个 hook 的共同基类）

```solidity
abstract contract BaseTickRangeHook is IBaseTickRangeHook, BaseHook, AccessControl {
    int24 public tickLowerBound;
    int24 public tickUpperBound;
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    function _beforeAddLiquidity(IPoolManager.ModifyLiquidityParams calldata params_) internal view {
        if (params_.tickLower < tickLowerBound || params_.tickUpper > tickUpperBound)
            revert InvalidTickRange(...);
    }

    function setTickRange(int24 lo, int24 hi) external onlyRole(MANAGER_ROLE) {
        _setTickRange(lo, hi);  // 要求 lo < hi
    }
}
```

- 只实现了 `beforeAddLiquidity`（无 delta），其余 flag 全 false → `vanillaSwap=True`
- 任何 `tickLower < tickLowerBound || tickUpper > tickUpperBound` 的 LP 操作一律 revert
- `MANAGER_ROLE` 可调整 tick 范围；`DEFAULT_ADMIN_ROLE` 可授予/撤销 `MANAGER_ROLE`

### 4.2 `TickRangeHook`（基类特化）

`TickRangeHook` 几乎只有构造函数 + 覆写 `_beforeAddLiquidity` 来调用 `super._beforeAddLiquidity(params_)`。它**只是把基类暴露成可独立部署的合约**，没有新增任何能力。

- 权限位：`beforeAddLiquidity`（继承自基类）
- 属性：`vanillaSwap=True, swapAccess=none`
- 不能阻止 swap；只能约束 LP 位置必须在 `[tickLowerBound, tickUpperBound]` 内

### 4.3 `AllowlistHook`（基类扩展）

`AllowlistHook is BaseTickRangeHook, PredicateClient`，**新增了 swapper allowlist、Router/PM trustlist、Predicate KYC、donation 拦截**：

```solidity
function _beforeSwap(address sender_, PoolKey calldata key_, SwapParams calldata params_, bytes calldata hookData_)
    internal override returns (bytes4, BeforeSwapDelta, uint24)
{
    if (isSwappersAllowlistEnabled) {
        if (!isSwapRouterTrusted(sender_)) revert SwapRouterNotTrusted(sender_);
        address caller_ = IBaseActionsRouterLike(sender_).msgSender();
        if (!isSwapperAllowed(caller_)) revert SwapperNotAllowed(caller_);

        if (!isPredicateCheckEnabled) {
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        PredicateMessage memory predicateMessage_ = abi.decode(hookData_, (PredicateMessage));
        bytes memory encodeSigAndArgs_ = abi.encodeWithSignature(
            "_beforeSwap(address,address,address,uint24,int24,address,bool,int256)",
            caller_, key_.currency0, key_.currency1, key_.fee, key_.tickSpacing,
            address(key_.hooks), params_.zeroForOne, params_.amountSpecified
        );
        if (!_authorizeTransaction(predicateMessage_, encodeSigAndArgs_, caller_, 0)) {
            revert PredicateAuthorizationFailed(caller_);
        }
    }
    return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
}
```

四层检查（顺序）：
1. **Swap Router trust** — `sender_`（也就是 PoolManager 传进来的 router 地址）必须在 `_swapRouters` 中，否则 revert
2. **Swapper allowlist** — router 通过 `IBaseActionsRouterLike.msgSender()` 拿到"最终用户地址"，必须在 `_swappersAllowlist` 中
3. **Predicate KYC**（可关）— `hookData_` 必须 `abi.encode(PredicateMessage)`，调用 `_authorizeTransaction(...)` 走链下签名的合规校验
4. 返回前 zero delta — `vanillaSwap=False`（因为拦截了 swap），但无 fee 抽成

`_beforeAddLiquidity`（允许 + tick 范围）：
```solidity
if (isLiquidityProvidersAllowlistEnabled) {
    if (!isPositionManagerTrusted(sender_)) revert PositionManagerNotTrusted(sender_);
    address caller_ = IBaseActionsRouterLike(sender_).msgSender();
    if (!isLiquidityProviderAllowed(caller_)) revert LiquidityProviderNotAllowed(caller_);
}
super._beforeAddLiquidity(params_);  // 继承自 BaseTickRangeHook 的 tick 检查
```

`_beforeDonate`：无条件 `revert DonationNotAllowed()` —— 禁掉所有 donate 路径。

**Predicate 集成**：通过 `predicate-contracts/src/mixins/PredicateClient.sol` 提供的 `_authorizeTransaction(predicateMessage_, encodeSigAndArgs_, caller_, 0)` 走链下签名验证（EIP-712-style）。`PredicateMessage` 是合规供应商的链上凭证，结构由供应商决定。

### 4.4 关键权限位对比

```
TickRangeHook:    { beforeAddLiquidity }
AllowlistHook:    { beforeAddLiquidity, beforeSwap, beforeDonate }
```

`AllowlistHook` 的 flags 同时含 `beforeSwap` 但 `beforeSwapReturnsDelta=false`、无 `afterSwap` → 实际效果是"拒绝/允许 swap 但不修改 swap 行为"，所以 `vanillaSwap=True` 在 AllowlistHook 也成立（按 5. 风险与限制中"vanillaSwap 的定义"判断：hook 仅做 access control，不修改 swap 数学、不取 delta、不嵌套 swap）。

但根据 hooklist schema 描述，AllowlistHook 的 `vanillaSwap` 字段未在元数据中显式声明，需要看 json 才能确认——本调研基于源码推导它**应该是 True**（仅 access control）。

### 4.5 管理权限

| 角色 | 默认 | 能力 |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | 构造函数传入的 `admin_` | grant/revoke `MANAGER_ROLE` |
| `MANAGER_ROLE` | 构造函数传入的 `manager_` | `setTickRange` / `setSwapper(s)` / `setLiquidityProvider(s)` / `setSwapRouter(s)` / `setPositionManager(s)` / `setSwappersAllowlist` / `setLiquidityProvidersAllowlist` / `setPredicateCheck` / `setPredicateManager` / `setPolicy` |

## 5. 时序图

**LP Deposit**（两个 hook 通用）：
```
PositionManager (trusted by AllowlistHook)
   │  modifyLiquidities([ModifyLiquidityParams{tickLower, tickUpper, ...}])
   ▼
PoolManager.unlock ──► hook.beforeAddLiquidity(sender=PM, key, params)
   │                       │
   │                       ├─ AllowlistHook: isPositionManagerTrusted(sender)?
   │                       │   ├─ 否 → revert PositionManagerNotTrusted
   │                       │   └─ 是 → IBaseActionsRouterLike(PM).msgSender() 拿 caller
   │                       │       → isLiquidityProviderAllowed(caller)?
   │                       │           ├─ 否 → revert LiquidityProviderNotAllowed
   │                       │           └─ 是 → 通过
   │                       │
   │                       └─ tickLower < tickLowerBound || tickUpper > tickUpperBound?
   │                           ├─ 是 → revert InvalidTickRange(...)
   │                           └─ 否 → 通过
   │
   └─ PoolManager 执行 LP 修改
```

**Swap**（仅 AllowlistHook）：
```
SwapRouter (trusted by AllowlistHook)
   │  execute(commands, inputs) → 内部调用 PoolManager.swap(key, params, hookData)
   ▼
PoolManager.unlock ──► hook.beforeSwap(sender=Router, key, params, hookData)
   │                       │
   │                       ├─ isSwapRouterTrusted(sender)?
   │                       │   ├─ 否 → revert SwapRouterNotTrusted
   │                       │   └─ 是 → IBaseActionsRouterLike(Router).msgSender() 拿 caller
   │                       │       → isSwapperAllowed(caller)?
   │                       │           ├─ 否 → revert SwapperNotAllowed
   │                       │           └─ 是 → 通过
   │                       │
   │                       ├─ isPredicateCheckEnabled?
   │                       │   ├─ 否 → return zero delta
   │                       │   └─ 是 → abi.decode(hookData, PredicateMessage)
   │                       │       → encodeSigAndArgs (caller, currency0, currency1, fee, tickSpacing, hooks, zeroForOne, amountSpecified)
   │                       │       → _authorizeTransaction(msg, sigAndArgs, caller, 0)
   │                       │           ├─ 失败 → revert PredicateAuthorizationFailed
   │                       │           └─ 成功 → 通过
   │                       │
   │                       └─ return zero delta
   │
   └─ PoolManager 执行标准 swap
```

**Donate**（仅 AllowlistHook）：
```
任意 sender
   │  poolManager.donate(key, amount0, amount1, hookData)
   ▼
hook.beforeDonate
   │
   └─ revert DonationNotAllowed   // 无条件拒绝
```

**Manager 调整 TickRange**：
```
Manager (MANAGER_ROLE)
   │  setTickRange(newLo, newHi)
   ▼
   require newLo < newHi (TicksOutOfOrder revert)
   └─ 写 tickLowerBound / tickUpperBound
        emit TickRangeSet(newLo, newHi)
```

## 6. 风险与限制

### 6.1 通用（两个 hook 共有）

1. **只约束 LP，不约束 swap 数学**：TickRangeHook 完全不动 swap 行为；如果用户用 0x 地址绕过 PM 直调 `PoolManager.modifyLiquidity`（无 hook 入口），仍受 `beforeAddLiquidity` 拦截——但前提是 hook flag 正确。
2. **Manager 角色是单点**：`MANAGER_ROLE` 可以单独调整 tick 范围或 allowlist——如果 `manager_` EOA 私钥泄露，整个池子的访问策略被单方面改写。
3. **不可升级**（`upgradeable=False`）：bug fix 必须重新部署、迁移 LP。
4. **审计缺失**（`auditUrl: ""`）：M0 Labs 公开的 hook 仓库在 github.com/M0Labs/ 但本部署未见独立审计报告。

### 6.2 TickRangeHook 特有

5. **过窄 tick 范围会卡流动性**：如果 manager 设的 `[lo, hi]` 与实际初始 tick 偏离太远，所有 LP 操作 revert，池子无法启动。
6. **`super._beforeAddLiquidity` 是 internal view**：没有 reentrancy guard，依赖 PoolManager unlock 模式。

### 6.3 AllowlistHook 特有

7. **`IBaseActionsRouterLike.msgSender()` 信任 router**：hook 信任 router 提供正确的"原始 caller"——如果 router 实现伪造 `msgSender()`（或被攻陷），攻击者可绕过 swappers allowlist。
8. **Router/PM trustlist 是中心化的**：manager 可以随时加入新 router，绕开原本"白名单"语义；外部观察者必须监控 `SwapRouterSet` / `PositionManagerSet` 事件。
9. **Predicate 链下签名依赖外部 KYC 方**：`predicateMessage_` 由供应商签发；如果供应商私钥泄露或合规策略变化，所有 swap 都被卡死或被定向放行。
10. **PredicateMessage 必须由 caller 提前获取**：用户在前端完成 KYC，拿到签名后 `abi.encode` 进 `hookData`——如果忘记填 `hookData` 且 `isPredicateCheckEnabled` 为 true，swap 会 revert；如果关闭，hook 等于"无 Predicate 校验"状态。
11. **Donate 无条件拒绝**：阻断所有 `poolManager.donate`——也阻断了潜在的 fee compounding 场景。
12. **BeforeSwap 强制要求 sender 是 trusted router**：用户直接 `poolManager.swap`（无 router 包装）会被 revert；这强制所有用户必须经 trusted router。
13. **`hookData` 解码失败 = 整个 swap revert**：`abi.decode(hookData_, (PredicateMessage))` 在 Predicate 启用状态下，如果 `hookData` 不是 PredicateMessage 编码，会 revert。普通 router 调用需要先做"获取签名 + 编码 hookData"两步骤。
14. **`_beforeSwap` 校验在 LP 校验之前**——意味着先做 swap access，再做 LP access；如果 manager 同时开启 `isSwappersAllowlistEnabled` 和 `isLiquidityProvidersAllowlistEnabled`，但只 trust 了一个 router，PM 的 LP 操作也会卡住。
15. **30d 交易量 0 / Pool 数 N/A**：实际生产部署可能需要信任名单、Predicate 集成、KYC 流程；目前未观察到该 hook 的活跃池子。

## 7. 与 Uniswap v4 标准的契合

| 项 | 状态 |
|---|---|
| `BaseHook` 派生 | ✓ |
| 地址 flags 与源码一致 | ✓（TickRangeHook：bit 11；AllowlistHook：bit 11 + bit 7 + bit 5） |
| `updateDynamicLPFee` | ✗（无 LP fee 覆盖） |
| `delta` 返回 | 全部 ZERO_DELTA |
| `noDelegateCall` | 继承自 `BaseHook` |
| `AccessControl` | ✓（OpenZeppelin 标准） |

两 hook 都是"轻度接入、合规导向"的实现——它们把 v4 的 hook 能力当作 gate 机制，而非 fee mechanism。非常适合机构 RWA、许可 DeFi、合规稳定币等场景；但不适用于追求 fee 收益的 LP 池。
