import json
import re
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
docs_dir = repo / "docs" / "hooksurvey"
dune_file = repo / "hook_volume_group_7614121.json"
hooks_dir = repo / "hooks" / "ethereum"

dune_by_addr = {}
if dune_file.exists():
    for r in json.loads(dune_file.read_text()).get("result", {}).get("rows", []):
        addr = str(r.get("hook_address", "")).strip().lower()
        if addr and addr not in dune_by_addr:
            dune_by_addr[addr] = r

def safe_dir_name(name):
    s = re.sub(r"[^A-Za-z0-9_.-]+", "_", name).strip("_")
    return s or "unnamed-hook"

def fmt_usd(v):
    if v is None:
        return "N/A"
    try:
        v = float(v)
    except (TypeError, ValueError):
        return str(v)
    if v >= 1_000_000_000:
        return f"${v/1_000_000_000:.2f}B"
    if v >= 1_000_000:
        return f"${v/1_000_000:.2f}M"
    if v >= 1_000:
        return f"${v/1_000:.2f}K"
    return f"${v:.2f}"

def active_flags(flags):
    return [k for k, v in flags.items() if v]

def props_to_text(props):
    return " ".join(f"`{k}={v}`" for k, v in props.items() if v)

existing_dirs = {p.name for p in docs_dir.iterdir() if p.is_dir()}
created = []
existing = []
for p in sorted(hooks_dir.glob("*.json")):
    data = json.loads(p.read_text())
    h = data.get("hook", {})
    addr = h.get("address", "").strip()
    name = h.get("name") or "Unknown"
    deployer = h.get("deployer") or "Unknown"
    desc = h.get("description") or ""
    audit = h.get("auditUrl") or ""
    flags = data.get("flags", {})
    props = data.get("properties", {})

    dir_name = safe_dir_name(name)
    target_dir = docs_dir / dir_name
    if target_dir.exists():
        existing.append(dir_name)
        continue
    target_dir.mkdir(parents=True, exist_ok=True)

    dune = dune_by_addr.get(addr.lower(), {})
    vol = fmt_usd(dune.get("total_volume_30d", 0))
    swaps = dune.get("swap_count_30d", "N/A")
    pools = dune.get("pool_count", "N/A")
    last_swap = dune.get("last_swap_at", "N/A")
    dune_project = dune.get("project", "N/A")

    aflags = active_flags(flags)
    ptext = props_to_text(props)

    desc_clean = desc.strip() or "_暂无描述_"
    if len(desc_clean) > 1200:
        desc_clean = desc_clean[:1200].rstrip() + "..."

    readme = f"""# {name}

> **地址**: [{addr}](https://etherscan.io/address/{addr})
> **链**: Ethereum (chainId=1)
> **部署方**: `{deployer}`
> **审计报告**: {audit if audit else "_无_"}
> **Dune label**: {dune_project}

## 基本信息

| 字段 | 值 |
|---|---|
| 名称 | {name} |
| 链 | Ethereum Mainnet |
| 30d 交易量 | {vol} |
| 30d Swap 数 | {swaps} |
| 关联 Pool 数 | {pools} |
| 最近 swap | {last_swap} |

## Hook 权限位

{", ".join(f"`{f}`" for f in aflags) if aflags else "_无_"}

## 属性

{ptext if ptext else "_无_"}

## 功能描述

{desc_clean}

## 调研结果 (待补充)

- 收益结构
- 工作原理
- 时序图
- 风险与限制
"""
    (target_dir / "README.md").write_text(readme)
    created.append(dir_name)

print(f"created={len(created)} already_exist={len(existing)}")
print("created_sample=", created[:10])
print("already_exist_sample=", existing[:5])
