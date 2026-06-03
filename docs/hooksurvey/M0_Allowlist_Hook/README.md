# M0 Allowlist Hook

> **地址**: [0xaf53cb78035a8e0acce38441793e2648b15b88a0](https://etherscan.io/address/0xaf53cb78035a8e0acce38441793e2648b15b88a0)
> **链**: Ethereum (chainId=1)
> **部署方**: `Unknown`
> **审计报告**: _无_
> **Dune label**: N/A

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | M0 Allowlist Hook |
| 链 | Ethereum Mainnet |
| 30d 交易量 | $0.00 |
| 30d Swap 数 | N/A |
| 关联 Pool 数 | N/A |
| 最近 swap | N/A |

## Hook 权限位

`beforeAddLiquidity`, `beforeSwap`, `beforeDonate`

## 属性

`requiresCustomSwapData=True` `swapAccess=allowlist`

## 功能描述

An access-control hook that restricts swaps to allowlisted addresses using the Predicate authorization system and restricts liquidity provision to approved providers; donations are blocked.

## 调研结果

> 📚 **系列调研**：本 hook 与 [M0 Tick Range Hook](../M0_Tick_Range_Hook/README.md) 共享同一个 `BaseTickRangeHook` 基类。完整对比、Tick 范围约束机制、Allowlist 体系、Predicate KYC 集成、管理员角色与时序图详见 [`family/m0-series.md`](../family/m0-series.md)。

### 收益结构

| 项 | 值 | 备注 |
|---|---|---|
| LP fee 抽成 | 无 | 不调用 `updateDynamicLPFee`，无 LP fee 覆盖 |
| Protocol fee | 无 | 0 protocol fee 抽成 |
| 计费币种 | — | — |
| 第三方 Predicate 授权费 | 由 Predicate 服务商收取 | 链下 KYC 商业模式，非 hook 本身收益 |
| `vanillaSwap` | True（推断） | hook 仅做 access control + 拦截 donate，不修改 swap 数学 |

### 工作原理（AllowlistHook 增量）

`AllowlistHook is BaseTickRangeHook, PredicateClient`，在基类之上叠加四层访问控制：

1. **Swap Router trust** — `_swapRouters[sender_]` 必须为 true，否则 `SwapRouterNotTrusted` revert
2. **Swapper allowlist** — `IBaseActionsRouterLike(sender_).msgSender()` 拿"原始 caller"，必须在 `_swappersAllowlist` 中
3. **Predicate KYC**（可关闭） — `hookData_` 必须 `abi.encode(PredicateMessage)`，通过 `_authorizeTransaction` 走链下签名验证
4. **Tick 范围**（继承自 BaseTickRangeHook） — `tickLower >= tickLowerBound && tickUpper <= tickUpperBound`

`LP` 路径除了上述 tick 检查，还需：
- `isPositionManagerTrusted(sender)`（PM 在 trustlist）
- `isLiquidityProviderAllowed(caller)`（通过 PM.msgSender() 拿到原始 LP）

`_beforeDonate` 无条件 `revert DonationNotAllowed()`。

### 时序图

**Swap (Trusted Router + Allowlisted Swapper + Predicate KYC)**:
```
SwapRouter (trusted)
   │  execute(...) → PoolManager.swap(key, params, hookData=abi.encode(PredicateMessage))
   ▼
hook.beforeSwap
   │
   ├─ isSwapRouterTrusted(Router)? 否 → revert
   ├─ caller = Router.msgSender()
   ├─ isSwapperAllowed(caller)? 否 → revert
   ├─ isPredicateCheckEnabled?
   │   ├─ 否 → return zero delta
   │   └─ 是 → _authorizeTransaction(msg, encodeSigAndArgs, caller, 0)
   │       └─ 失败 → revert PredicateAuthorizationFailed
   └─ return zero delta
```

### 风险与限制

1. **manager 单点**：单一 `MANAGER_ROLE` 可改 tick 范围、allowlist、Predicate 配置、Router/PM trustlist——私钥泄露=整个策略改写。
2. **`IBaseActionsRouterLike.msgSender()` 信任 router**：router 被攻陷或伪造 `msgSender()`，allowlist 可被绕过。
3. **Predicate 链下签名依赖外部 KYC 方**：供应商私钥泄露或合规策略变化 → swap 全部卡死或被定向放行。
4. **`hookData` 解码失败 = revert**：普通 router 若不携带 PredicateMessage 编码，swap 直接 revert（Predicate 启用状态）。
5. **Donate 无条件拒绝**：所有 `poolManager.donate` 调用 revert。
6. **不可升级**（`upgradeable=False`），但**可管理**——通过 `AccessControl` 角色可换 manager/替换 Predicate policy。
7. **审计缺失**（`auditUrl: ""`）。
8. **30d 交易量 0 / 关联 Pool 数 N/A**：本部署未观察到生产使用，可能为 M0 Labs 内部/合作伙伴测试部署。
