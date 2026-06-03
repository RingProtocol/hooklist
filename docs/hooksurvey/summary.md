# Hook 价值调研总结

> 调研范围：`docs/hooksurvey/` 下收录的 50+ 个 Uniswap v4 hook
> 调研目的：识别最有价值的 hook 设计，并给出 Ring Protocol 的可借鉴路径
> 数据基线：Dune 30d 交易量 / 主网部署状态

---

## 一、按"价值/启发性"分层

### 🥇 S 级：已经在主网验证 + 真正解决问题

| Hook | 30d 量 | 价值点 | Ring 可借鉴度 |
|---|---|---|---|
| **Angstrom** (Sorella) | $268M | 应用专属拍卖内化 MEV，把价值还给 LP/trader | ★★★★（设计思路） |
| **BunniHook** (Bunni v2) | 持续高 | Surge fee + am-AMM bidding + FloodPlain rebalance，是 v4 hook 体系的天花板 | ★★★★★（直接照搬模式） |
| **StableStableHook** (Uniswap 官方) | $74M | 动态费率 = base × exp(α×deviation)，极简优雅 | ★★★★★（可内嵌到 Few 系列） |
| **WETHHook** (Uniswap 官方) | $18M | ETH↔WETH 1:1 wrap/unwrap via delta，与 Ring Few 系列同构 | ★★★★★（设计参照） |
| **M0 AllowlistHook** | $0（未上线池） | 链上 KYC + 池子 ACL，合规/机构池的标配 | ★★★★（如果做 RWA fewToken） |

### 🥈 A 级：模式创新，单点强

| Hook | 价值点 |
|---|---|
| **Sat1 Hook** (#1 体量) | RFQ-style P2P 撮合，单 hook 37505 swaps/30d |
| **VirtualLBP** (Aztec CCA) | 不抽费，做"拍卖守门员"，证明 hook 可以是治理组件 |
| **TokenWorks v2/v4** | 时间衰减买卖税模型 (99%→10%)，是 launchpad 经济范本 |
| **M0 TickRangeHook** | 只约束 LP 位置不动 swap 数学——"轻度 hook"代表 |
| **UpegHook** | 9 pool × 41569 swaps 共享一个 hook，多 pool 复用的好例子 |

### 🥉 B 级：值得参考但未验证

| Hook | 价值点 |
|---|---|
| **EMADynamicFeeHook** | EMA 价格 + 30 段费率表 + 300-block anti-JIT，immutable |
| **BVCC Dynamic Fee** | gas × vol × volume × repeat-penalty 多维费率（功能多但复杂） |
| **TokenWorks v3/v5** | 系列演进过程，本身价值在演化史 |
| **WstETHHook** | 与 Ring Few 同构，但额外使用**动态 stETH/wstETH 汇率**（关键差异） |

---

## 二、Ring Protocol 该学什么（按优先级）

### 1. 【最该学】BunniHook 的 surge fee + am-AMM

Ring Few 池子现在是"裸 v4 + wrap"——LP 承担所有 LVR，套利者免费吃肉。

- **Surge fee**：当 fewToken 价格被砸偏离锚定价时自动加 fee，抑制套利
- **am-AMM bidding**：让第三方对"未来一段 swap 流"出价，把 LVR 内化给 LP
- 这是把"1:1 wrap 池"从被动变成**主动收益增强**的关键

### 2. 【强烈建议】StableStableHook 的动态费率直接套到 Few Stable 池

`FewUSDC` / `FewUSDT` / `FewDAI` 三个池子之间互相套利是常态。

- 当前 `fee_in_percent = 0` 已经是痛点（[ringhook_dune.sql](file:///Users/alexla/code/ringprotocol/hooklist/docs/dune/ringhook_dune.sql) 注释里也提到）
- 直接照搬 Uniswap 官方的 `base × exp(α×deviation)` 公式，2 周可上线
- 预计能把 fewStable 池 LP 收益提升 5–15 bps

### 3. 【必须学】WstETHHook 的动态汇率 wrap

对照看 [Ring Few ETH Hook](file:///Users/alexla/code/ringprotocol/hooklist/docs/hooksurvey/Ring_Few_ETH_Hook) vs [WstETHHook](file:///Users/alexla/code/ringprotocol/hooklist/docs/hooksurvey/WstETHHook)：

- Ring Few 是**静态 1:1** wrap（只适合 fully-backed 资产）
- WstETHHook 在 `beforeSwap` 里**调用 stETH.wrap/unwrap 拿到实时汇率**
- Ring 后续如果接 LST（weETH、wstETH）或者 rebasing token，**必须**改成动态汇率版本——否则会出严重套利

### 4. 【中期】M0 AllowlistHook 的 Predicate 合规层

如果 Ring 想做"机构池"（受监管的稳定币、RWA fewToken），直接复用 M0 模式：

- Tick 范围 + LP/Swapper allowlist
- Predicate 链下 KYC 签名
- 区别只在于把 fewToken 工厂地址塞进 allowlist

### 5. 【锦上添花】TokenWorks 的衰减税模型用于新 fewToken 启动

新 fewToken 上市时，可以借鉴：

- 99% → 10% 衰减的 buy tax 防止 sniper
- 固定 sell tax 给 fewToken 协议积累
- 但这是"创作者经济"路线，谨慎评估 token 团队是否接受

---

## 三、不建议学的（避坑）

- **BunniHook 全套（rebalance / FloodPlain）**：复杂度太高，是专业 CL 协议才能 hold 住的；Ring Few 池子规模还不到需要自动 rebalance 的程度
- **Angstrom 的拍卖模式**：需要自建 Solver 网络和 EIP-712 订单簿，运营成本远超 wrap 类业务
- **BVCC 的多维 gas/vol/volume 复合费率**：参数面太复杂，对 fewToken 1:1 锚定池子属于过度设计
- **M0 AllowlistHook 的"无条件 reject donate"**：阻断 `poolManager.donate` 也会阻断潜在 fee compounding

---

## 四、一句话总结

> Ring Few 系列已经验证了"wrap as hook"的模式（= WETHHook + WstETHHook 简化版），下一步要的不是新 hook 类型，而是给现有池子装"费率脑子"——具体路径 = 抄 StableStableHook 的动态费率 + 抄 BunniHook 的 surge fee。

这两步做完，Ring Few 池子的 LP 收益能直接上一个台阶，护城河也比单纯的"包一层 ERC20"深得多。
