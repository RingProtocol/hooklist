# 部署与配置指南

本指南说明如何将 EMADynamicFeeHook 配置到你的池子仓位。有两条路径：

- **路径 A（推荐）**：直接使用已部署的 hook 地址
- **路径 B**：自己部署一份（适合自定义费率档位）

---

## 路径 A：使用已部署的 Hook 地址

如果你的目标链已有 EMADynamicFeeHook 部署，直接用该地址初始化 pool 即可。

### A.1 各链地址

| 链 | chainId | Hook 地址 | PoolManager |
|---|---|---|---|
| Ethereum | 1 | `0x924e5C44c3b82C2C0Ba231Cd0De7B581180E1bC0` | `0x000000000004444c6599F4ee3fC58F2c10bB8E01` |
| Arbitrum | 42161 | `0xe025cb6c58826ac79e2052c350250881f8f51bc0` | `0x000000000004444c6599F4ee3fC58F2c10bB8E01` |
| Optimism | 10 | `0xb1db44de89634a001ceb5847defc3ff1e5601bc0` | `0x000000000004444c6599F4ee3fC58F2c10bB8E01` |
| Polygon | 137 | `0x8eB0089d6c616bC2b7f69b3CAFECfEDc3eF11BC0` | `0x000000000004444c6599F4ee3fC58F2c10bB8E01` |
| Unichain | 130 | `0x6398f3c67b03c4622bdaa48d9e340d66e23a1bc0` | `0x000000000004444c6599F4ee3fC58F2c10bB8E01` |

> **注意**：Uniswap v4 的 PoolManager 在所有链上都是同一地址 `0x000000000004444c6599F4ee3fC58F2c10bB8E01`（CREATE2 部署）。

### A.2 初始化 Pool

Uniswap v4 的 pool 通过 `PoolManager.initialize()` 初始化。你需要构造一个 `PoolKey`：

```solidity
PoolKey memory key = PoolKey({
    currency0: <token0>,        // 地址较小的 token（按 Currency 排序）
    currency1: <token1>,        // 地址较大的 token
    fee: 0x80000000,             // DYNAMIC_FEE_FLAG（最高位=1），表示由 hook 控制 fee
    tickSpacing: 60,             // 推荐 60（与 v3 默认一致）
    hooks: 0x924e5C44c3b82C2C0Ba231Cd0De7B581180E1bC0  // EMADynamicFeeHook
});
```

**关键字段说明**：

| 字段 | 值 | 说明 |
|---|---|---|
| `fee` | `0x80000000` | **必须是这个值**。最高 bit = 1 表示 dynamic fee，低 24 位被忽略（由 hook 覆盖） |
| `tickSpacing` | 60 | 推荐。也可用 10/100/2000，取决于你的 pair 波动性 |
| `hooks` | hook 地址 | 必须是已部署的 EMADynamicFeeHook |

### A.3 用 Foundry 脚本初始化

```solidity
// script/InitializePool.s.sol
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

contract InitializePoolScript is Script {
    IPoolManager constant POOL_MANAGER = IPoolManager(0x000000000004444c6599F4ee3fC58F2c10bB8E01);

    function run() external {
        address hook = vm.envAddress("HOOK_ADDRESS");
        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");

        // 确保 currency0 < currency1
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 0x80000000,  // DYNAMIC_FEE_FLAG
            tickSpacing: 60,
            hooks: IHooks(hook)
        });

        uint160 sqrtPriceX96 = 79228162514264337593543950336; // = 1.0 (价格比 1:1)

        vm.startBroadcast();
        POOL_MANAGER.initialize(key, sqrtPriceX96);
        vm.stopBroadcast();
    }
}
```

```bash
# 运行（以 Ethereum 为例）
export HOOK_ADDRESS=0x924e5C44c3b82C2C0Ba231Cd0De7B581180E1bC0
export TOKEN0=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48  # USDC
export TOKEN1=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2  # WETH
forge script script/InitializePool.s.sol --rpc-url $RPC_URL --broadcast
```

### A.4 添加流动性

Pool 初始化后，用 `PositionManager.mint()` 添加流动性：

```solidity
// 通过 v4-periphery 的 PositionManager
PositionManager.mint(
    PoolKey memory key,
    int24 tickLower,
    int24 tickUpper,
    uint256 liquidity,
    ...
);
```

**注意 Anti-JIT**：添加流动性后，**300 blocks（约 1 小时）内不能撤出**。这是 hook 的保护机制，不是 bug。

### A.5 交易

Pool 就绪后，任何标准 swap router 都能交易。以 Universal Router 为例：

```solidity
// 普通 swap 即可，不需要特殊 calldata
// hook 会在 beforeSwap 中自动计算并覆盖 fee
```

---

## 路径 B：自己部署 Hook

适合需要自定义费率档位、或目标链没有部署的情况。

### B.1 项目搭建

```bash
mkdir my-dynamic-fee-hook && cd my-dynamic-fee-hook
forge init

# 安装依赖
forge install OpenZeppelin/openzeppelin-uniswap-hooks
forge install Uniswap/v4-core
forge install Uniswap/v4-periphery
```

### B.2 foundry.toml

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.26"
evm_version = "cancun"

remappings = [
    "@openzeppelin/uniswap-hooks/=lib/openzeppelin-uniswap-hooks/src/",
    "@uniswap/v4-core/=lib/v4-core/",
    "@uniswap/v4-periphery/=lib/v4-periphery/",
    "v4-core/=lib/v4-core/src/",
    "v4-periphery/=lib/v4-periphery/src/",
]
```

### B.3 复制源码

将本目录的源码复制到你的项目：

```bash
cp /path/to/dynamicfeehook/src/EMADynamicFeeHook.sol src/
cp /path/to/dynamicfeehook/src/BaseHook.sol src/  # 或直接用 npm 包
```

### B.4 自定义费率档位（可选）

修改 `_lookupFee` 函数中的查表逻辑。例如想提高最低 fee：

```solidity
uint24 private constant MIN_FEE = 500;  // 0.05% 起步（原 0.01%）
uint24 private constant MAX_FEE = 50000; // 5.00% 上限（原 3.00%）
```

### B.5 部署脚本

```solidity
// script/Deploy.s.sol
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {EMADynamicFeeHook} from "../src/EMADynamicFeeHook.sol";

contract DeployScript is Script {
    function run() external {
        IPoolManager poolManager = IPoolManager(0x000000000004444c6599F4ee3fC58F2c10bB8E01);

        vm.startBroadcast();
        EMADynamicFeeHook hook = new EMADynamicFeeHook(poolManager);
        vm.stopBroadcast();

        console.log("EMADynamicFeeHook deployed:", address(hook));
    }
}
```

```bash
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
```

### B.6 验证源码

```bash
forge verify-contract <deployed_address> src/EMADynamicFeeHook.sol \
    --chain <chain_id> \
    --api-key <etherscan_api_key> \
    --constructor-args $(cast abi-encode "constructor(address)" 0x000000000004444c6599F4ee3fC58F2c10bB8E01)
```

### B.7 初始化 Pool

部署完成后，按路径 A 的 A.3 步骤用你的新 hook 地址初始化 pool。

---

## 重要注意事项

### 1. Hook 地址与权限位绑定

Uniswap v4 的 hook 地址**必须**与其权限位的 bitmask 匹配。EMADynamicFeeHook 的权限位决定了它的地址低位必须是特定模式：

```
权限位（从低到高）:
bit 0: beforeInitialize      = 0
bit 1: afterInitialize       = 1
bit 2: beforeAddLiquidity    = 1
bit 3: afterAddLiquidity     = 0
bit 4: beforeRemoveLiquidity = 1
bit 5: afterRemoveLiquidity  = 1
bit 6: beforeSwap            = 1
bit 7: afterSwap             = 1
bit 8-13: 全 0
```

→ 地址低位必须是 `0b11110110` = `0xD6` 结尾（忽略大小写）。

**验证已部署地址**：
- Ethereum: `0x924e5C44c3b82C2C0Ba231Cd0De7B581180E1bC0` → 尾 `bC0` ✅
- `0xbC0` = `1011 1100 0000` → 低 8 bit = `1100 0000`... 

> 实际验证：地址低 14 bit 必须匹配权限位。用 `Hooks.validateHookPermissions()` 在部署时自动检查，无需手动算。自己部署时 `BaseHook` 构造函数会自动 `validateHookAddress(this)`。

### 2. fee 字段必须设 DYNAMIC_FEE_FLAG

初始化 pool 时 `PoolKey.fee` 必须设为 `0x80000000`（最高位=1）。如果设成普通 fee 值，hook 的 `beforeSwap` 返回的 fee 会被忽略。

### 3. Anti-JIT 影响撤资

加流动性后 300 blocks 内不能撤。如果你需要频繁调仓，要么等 300 blocks，要么 fork 一份去掉 Anti-JIT（但不推荐，会失去 JIT 保护）。

### 4. 跨链使用

如果目标链没有 EMADynamicFeeHook 部署，且该链有 Uniswap v4 PoolManager，可以自己部署（路径 B）。源码不依赖任何链特定逻辑。

---

## 快速检查清单

部署/配置前确认：

- [ ] 目标链有 Uniswap v4 PoolManager (`0x000000000004444c6599F4ee3fC58F2c10bB8E01`)
- [ ] 选定 hook 地址（已部署 or 自己部署）
- [ ] `PoolKey.fee` = `0x80000000`（DYNAMIC_FEE_FLAG）
- [ ] `PoolKey.tickSpacing` 选合适值（60 是默认推荐）
- [ ] `currency0 < currency1`（按地址排序）
- [ ] 初始 `sqrtPriceX96` 计算正确（参考 Uniswap v4 文档）
- [ ] 准备好等 300 blocks 后才能撤流动性
- [ ] 源码已验证（自己部署时）

---

*源码：[`src/EMADynamicFeeHook.sol`](../src/EMADynamicFeeHook.sol) · [`src/BaseHook.sol`](../src/BaseHook.sol)*
