# 68 个 Dynamic Fee Hook 横向对比

按"可直接配置到自己池子使用"的适用性分三档。

**列说明**：Immut = immutable（无 owner/admin），Verif = 源码已验证，StdSwap = 不需要 custom swap data（标准 router 可调用），Access = swapAccess。

---

## 一、S 级：推荐直接使用

满足全部条件：immutable + 源码验证 + 标准 swap + swapAccess=none + 任意 pair 通用 + 代码简单。

| Hook | 链 | 地址 | Immut | Verif | StdSwap | Access | Flags |
|---|---|---|---|---|---|---|---|
| **EMADynamicFeeHook** | ethereum | `0x924e5C44c3b82C2C0Ba231Cd0De7B581180E1bC0` | ✅ | ✅ | ✅ | none | afterInitialize, beforeAddLiquidity, beforeRemoveLiquidity, afterRemoveLiquidity, beforeSwap, afterSwap |
| **EMADynamicFeeHook** | arbitrum | `0xe025cb6c58826ac79e2052c350250881f8f51bc0` | ✅ | ✅ | ✅ | none | 同上 |
| **EMADynamicFeeHook** | optimism | `0xb1db44de89634a001ceb5847defc3ff1e5601bc0` | ✅ | ✅ | ✅ | none | 同上 |
| **EMADynamicFeeHook** | polygon | `0x8eB0089d6c616bC2b7f69b3CAFECfEDc3eF11BC0` | ✅ | ✅ | ✅ | none | 同上 |
| **EMADynamicFeeHook** | unichain | `0x6398f3c67b03c4622bdaa48d9e340d66e23a1bc0` | ✅ | ✅ | ✅ | none | 同上 |

> **EMADynamicFeeHook 是唯一在 5 条链上都有部署的 dynamic fee hook**，源码一致，行为可预测。详见 [03-EMA_DYNAMIC_FEE_HOOK.md](03-EMA_DYNAMIC_FEE_HOOK.md)。

---

## 二、A 级：特定场景可用，但有局限

这些 hook 也 immutable + 源码验证，但只适合特定场景（特定 token、特定 pair、需要 custom data 等）。

### 2.1 稳定币对专用

| Hook | 链 | 地址 | 局限 |
|---|---|---|---|
| StableStableHook | ethereum | `0x4509b7eb3f9641226804fea4976963435d1c6080` | 需要配置锚定价格，只适合稳定币/稳定币对 |
| Renzo Hook | unichain | `0x09dea99d714a3a19378e3d80d1ad22ca46085080` | 专为 ETH/ezETH peg 稳定性设计 |

### 2.2 MEV/反机器人方向

| Hook | 链 | 地址 | 局限 |
|---|---|---|---|
| Custom Fee MEV Protection Hook | ethereum | `0xd5770936a6678353f1b17c342b29c4416b029080` | 方向性 buy/sell fee，有 blacklist（中心化风险） |
| Slippage Fee Hook | arbitrum | `0xc4bf39a096a1b610dd6186935f3ad99c66239080` | 基于 price impact 的 fee，仅 beforeSwap |
| MEVTaxTestInProd | unichain | `0xb9a17e66db950e00822c2b833d6bb304c9b86080` | priority-fee 比例 MEV 税，实验性 |
| Nuclear Man's Pool Trader Hook | ethereum | `0x000b70f7cd351f7479d1aa6f1354d32ed8821080` | 依赖外部 Uniswap V2 pair 做波动率参考 |

### 2.3 Surge / Oracle 类型（较复杂）

| Hook | 链 | 地址 | 局限 |
|---|---|---|---|
| Aegis | ethereum | `0x8f29bd5c8429730fa4c46e6295c4e679ededd0cc` | 依赖外部 DynamicFeeManager，收 hook fee + protocol fee |
| Aegis v1 Hook | unichain | `0x27bfccf7fdd8215ce5dd86c2a36651d05c8450cc` | 同上，truncated geometric oracle |
| Aegis v2 Hook | unichain | `0xa0b0d2d00fd544d8e0887f1a3cedd6e24baf10cc` | 同上 |
| Aegis v3 Hook | unichain/base | `0x88c9ff9fc0b22cca42265d3f1d1c2c39e41cdacc` | 同上，最完整版本 |
| Aegis V1.1 | polygon | `0x15cD9520D0fAF71c938Db4426F8C58B5cBAa9ACc` | 同上 |
| Aegis DFM | monad | `0xe620421BDE7D6A367d2c3b7E8dfA09B90AEa90CC` | 同上 |
| BunniHook | ethereum | `0x00001f3b9712708127b1fcad61cb892535951888` | 25K+ 字节，依赖 am-AMM/Flood/Solady，极复杂 |

### 2.4 EMA 同构（EMADynamicFeeHook 的 fork）

| Hook | 链 | 地址 | 说明 |
|---|---|---|---|
| Hook_V2 | base | `0x84129dc46b712614471131e8b9dadd64c7d21bc0` | EMA 30-step，与 EMADynamicFeeHook 描述一致，Base 链版本 |
| DynamicFeeHook | base | `0xbD2597a08627F119ED50C1A252f888F5BFd31B80` | 14 档 (0.03%–1.00%)，有 anti-JIT |

### 2.5 限价订单类（dynamic fee 是副产物）

| Hook | 链 | 地址 | 局限 |
|---|---|---|---|
| Limit Order Hook | arbitrum | `0xd73339564ac99f3e09b0ebc80603ff8b796500c0` | 限价订单功能为主 |
| Limit Order Hook | base | `0x9d11f9505ca92f4b6983c1285d1ac0aaff7ec0c0` | 同上 |
| Limit Order Hook | unichain | `0x2016c0e4f8bb1d6fea777dc791be919e2eda40c0` | 同上 |

### 2.6 其他 A 级

| Hook | 链 | 地址 | 局限 |
|---|---|---|---|
| VolumeDynamicFeeHook | optimism | `0x2c3254da64956f495356a482d51e7311347f5044` | 基于交易量 EMA，cycle floor/cash/elevated |
| AlphixLVRFee | base | `0x7cBbfF9C4fcd74B221C535F4fB4B1Db04F1B9044` | admin 可调 fee，非完全 immutable 逻辑 |
| Zora Hook | base | `0x0469a4Bd3724DC86C9542F4694c976DA13C450c0` | Zora Coins 专用，launch fee 99%→1% 衰减 |
| ZoraV4CoinHook | base | `0xF6d0A13609bb5779Bc5D639F2bA3Bfda83D4D0C0` | Zora 协议专用 |

---

## 三、B 级：不建议直接使用

原因：需要 custom swap data（标准 router 无法调用）、有 access control 限制、或属于特定平台 launch hook。

### 3.1 需要 custom swap data（标准 router 不可直接调用）

| Hook | 链 | 地址 |
|---|---|---|
| Angstrom | ethereum | `0x0000000aa232009084Bd71A5797d089AA4Edfad4` |
| Clanker Static Fee Hook | ethereum | `0x6c24d0bcc264ef6a740754a11ca579b9d225e8cc` |
| Clanker Dynamic Fee Hook v2 (Base) | base | `0xd60d6b218116cfd801e28f78d011a203d2b068cc` |
| Clanker Static Fee Hook v2 (Base) | base | `0xb429d62f8f3bffb98cdb9569533ea23bf0ba28cc` |
| Deli Hook (Base) | base | `0x570a48f96035c2874de1c0f13c5075a05683b0cc` |
| Fey Hook (Base) | base | `0x5b409184204b86f708d3aebb3cad3f02835f68cc` |
| Zora Post Hook v2.4.0 (Base) | base | `0xe2b4100de1cd284bd364f738d1354715515c90c0` |

### 3.2 有 access control / 平台专用

| Hook | 链 | 地址 | 原因 |
|---|---|---|---|
| Alphix | arbitrum | `0x5e645C3D580976Ca9e3fe77525D954E73a0Ce0C0` | swapAccess=governance |
| SafeSwap | arbitrum | `0x3e61d0519d598bf2dfaef5b8fa0256bf7e1d60c0` | swapAccess=temporal |
| Findex Hook (Optimism) | optimism | `0xb35297543d357ef62df204d8c3bd0e96038cf440` | 白名单限制 init/liquidity |
| Arrakis Private Hook (Ethereum) | ethereum | `0xf9527fb5a34ac6fbc579e4fbc3bf292ed57d4880` | 私有金库，限制 LP |
| Arrakis Private Hook (Base) | base | `0xf9527fb5a34ac6fbc579e4fbc3bf292ed57d4880` | 同上 |
| SwayHookJIT | base | `0x994f0eefe7a9857698218205b721466ef0038ac0` | swapAccess=governance |
| tokens.fun HookDynamicFee | base | `0xab29E4cb49980a6aC152515bb69470e0dEDC68cC` | swapAccess=temporal，平台专用 |
| tokens.fun HookDynamicFeeV2 | base | `0x7deBE6943ACEFE85c4EE81Aadd736466e07528cC` | 同上 |
| MoonpotHook | base | `0x6145a9cd8d6b597af774ea95b73684416848e088` | TMP/USDC 专用，floor-price defense |

### 3.3 Clanker / BVCC / Liquid / tokens.fun 平台系列

这些是各 launchpad 平台自己的 hook，绑定特定平台代币部署逻辑，不适合通用池：

| Hook | 链 |
|---|---|
| Clanker Dynamic Fee Hook (Arbitrum/Base/Unichain) | arbitrum, base, unichain |
| Clanker Static Fee Hook (Arbitrum/Base/Unichain) | arbitrum, base, unichain |
| ClankerHookDynamicFee / V2 (BNB) | bnb |
| ClankerHookStaticFee / V2 (BNB) | bnb |
| ClawnchHookStaticFeeV2 (Base) | base |
| BVCC Dynamic Fee Hook (Ethereum/Arbitrum/Base/BNB) | ethereum, arbitrum, base, bnb |
| LiquidHookDynamicFeeV2 (Base) | base |
| LiquidHookStaticFeeV2 (Base) | base |
| tokens.fun HookStaticFee / V2 (Base) | base |
| DecayMulticurveInitializerHook (Base) | base |
| TaxHook (Ethereum) | ethereum |
| Token Flow Tax Hook (Ethereum) | ethereum |
| CustomHook (Ethereum) | ethereum — 可升级 ❌ |

---

## 四、选择结论

```
对于"直接配置到自己池子仓位使用"的需求：

  EMADynamicFeeHook（5 链部署）
    ✅ 完全 immutable，无 owner
    ✅ 源码已验证，~170 行
    ✅ 任意 pair 通用（EMA 自参考）
    ✅ 标准 swap 兼容（不需要 custom data）
    ✅ swapAccess = none（任何人可交易）
    ✅ Anti-JIT 300 blocks
    ✅ 30 档费率 0.01% → 3.00%
    ✅ 多链部署验证一致性

  → 唯一满足所有 P0 + P1 标准的 hook
```

---

*数据来源：`hooks/*/*.json` + Etherscan 已验证源码，详见 [hooks-dynamic-fee.json](../hooks-dynamic-fee.json)*
