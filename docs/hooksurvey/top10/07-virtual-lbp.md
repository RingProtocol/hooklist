# VirtualLBPStrategyBasic (Aztec CCA)

> **地址**: [0xd53006d1e3110fd319a79aeec4c527a0d265e080](https://etherscan.io/address/0xd53006d1e3110fd319a79aeec4c527a0d265e080)
> **Dune label**: Aztec CCA
> **30d 交易量**: $54.98M | **30d Swap 数**: 28380 | **Pool 数**: 1
> **项目**: Aztec (推测)

> ⚠️ 详细调研请见独立文档: [VirtualLBPStrategyBasic/README.md](../VirtualLBPStrategyBasic/README.md)

## 1. 简版

| 维度 | 说明 |
|---|---|
| 收入来源 | **不抽取**任何费用 |
| 业务定位 | 拍卖守门员 + Virtual LBP |
| 配套体系 | ContinuousClearingAuction + IVirtualERC20 |
| `vanillaSwap` | `true` |
| `swapAccess` | `governance` |

## 2. 收益结构

- **Hook 本身不收任何费用** (`vanillaSwap: true`)
- 间接收益来自上层 [ContinuousClearingAuction](../) 体系
- Aztec (CCA) 通过拍卖 + 迁移服务收费

## 3. 与 Top 10 中其它 hook 的对比

| 维度 | VirtualLBP | LivoSwapHook | LaunchHook | StableStableHook |
|---|---|---|---|---|
| 直接抽费 | ❌ | ✅ (1%+tax) | ✅ (2%) | ✅ (dynamic) |
| vanillaSwap | ✅ | ❌ | ❌ | ❌ |
| 业务核心 | 拍卖守门 | 创作者税收 | 平台税 | 稳定币优化 |

## 4. 总结

VirtualLBP 在 Top 10 中是**唯一不直接抽费**的 hook，但通过"拍卖 + 守门"保护 Aztec CCA 体系不被打抢。
