#!/usr/bin/env python3
"""
Dune Dashboard Sync — 把本地 SQL 文件同步到已建好的 Dune query。

Dune 官方 API 不开放 dashboard/visualization 的创建/编辑端点,
所以本脚本只负责"同步 query 定义"。dashboard 容器本身需要在 Dune UI 里手建一次,
把每个 widget 绑到一个已存在的 query (URL 形如 https://dune.com/queries/<id>)。

前置步骤 (在 UI 里做一次):
  1. 打开 dashboard, 手动新建 4 个空 query (01_pool_summary / 02_token_reserves / ...)
  2. 把每个 query 加为 widget, 记录 query_id
  3. 在 docs/dune/dashboard/queries.json 里写好映射

然后日常只需:
  python3 scripts/dune_dashboard_sync.py            # 只同步 SQL 定义
  python3 scripts/dune_dashboard_sync.py --execute  # 同步 + 触发重新跑
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

import requests

# 复用 dune_run.py 的 .env 加载方式
env_path = Path(__file__).resolve().parent.parent / ".env"
if env_path.exists():
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        if k.strip() == "DUNE_API_KEY":
            os.environ["DUNE_API_KEY"] = v.strip()

API_KEY = os.environ.get("DUNE_API_KEY")
if not API_KEY:
    print("DUNE_API_KEY not set", file=sys.stderr)
    sys.exit(1)

BASE = "https://api.dune.com/api/v1"
HEADERS = {"X-Dune-Api-Key": API_KEY, "Content-Type": "application/json"}


def strip_sql_comments(sql: str) -> str:
    """去掉 -- 单行注释, 保持和 dune_run.py 一致的执行语义."""
    return "\n".join(
        line for line in sql.splitlines()
        if not line.strip().startswith("--")
    )


def patch_query(query_id: int, name: str, sql: str) -> dict:
    """同步 query_sql + name 到已存在的 Dune query."""
    r = requests.patch(
        f"{BASE}/query/{query_id}",
        headers=HEADERS,
        json={"query_sql": sql, "name": name},
        timeout=60,
    )
    if r.status_code != 200:
        raise RuntimeError(
            f"PATCH /query/{query_id} failed: {r.status_code} {r.text[:300]}"
        )
    return r.json()


def execute_query(query_id: int) -> str:
    """触发一次执行, 返回 execution_id (不阻塞等待结果)."""
    r = requests.post(
        f"{BASE}/query/{query_id}/execute",
        headers=HEADERS,
        json={"performance": "medium"},
        timeout=60,
    )
    if r.status_code != 200:
        raise RuntimeError(
            f"POST /query/{query_id}/execute failed: {r.status_code} {r.text[:300]}"
        )
    return r.json()["execution_id"]


def read_query(query_id: int) -> dict:
    """读 query 当前定义, 用于 dry-run 模式下 diff."""
    r = requests.get(
        f"{BASE}/query/{query_id}",
        headers=HEADERS,
        timeout=30,
    )
    if r.status_code != 200:
        return {"error": f"{r.status_code} {r.text[:200]}"}
    return r.json()


def load_map(map_path: Path) -> dict:
    """读 {filename: query_id} 映射 JSON. 文件名相对 dashboard/ 目录解析."""
    if not map_path.exists():
        print(f"map file not found: {map_path}", file=sys.stderr)
        sys.exit(1)
    data = json.loads(map_path.read_text())
    if not isinstance(data, dict):
        print("map JSON must be {filename: query_id}", file=sys.stderr)
        sys.exit(1)
    return data


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument(
        "--map",
        default="docs/dune/dashboard/queries.json",
        help="file → query_id 映射 JSON 路径 (默认: docs/dune/dashboard/queries.json)",
    )
    ap.add_argument(
        "--sql-dir",
        default="docs/dune/dashboard",
        help="SQL 文件所在目录 (默认: docs/dune/dashboard)",
    )
    ap.add_argument(
        "--dashboard-url",
        default="https://dune.com/ring_protocol/ring-hook-monitor",
        help="dashboard URL (只用于结尾打印, 不调 API)",
    )
    ap.add_argument(
        "--execute", action="store_true",
        help="同步后立即触发每个 query 重跑",
    )
    ap.add_argument(
        "--dry-run", action="store_true",
        help="只打印 diff, 不调 PATCH",
    )
    args = ap.parse_args()

    sql_dir = Path(args.sql_dir).resolve()
    map_data = load_map(Path(args.map).resolve())

    print(f"→ Dashboard: {args.dashboard_url}")
    print(f"→ SQL dir:   {sql_dir}")
    print(f"→ Map file:  {args.map}  ({len(map_data)} entries)")
    print(f"→ Mode:      {'DRY-RUN' if args.dry_run else ('SYNC+EXECUTE' if args.execute else 'SYNC')}\n")

    rows = []
    for filename, query_id in map_data.items():
        sql_path = sql_dir / filename
        if not sql_path.exists():
            print(f"[skip] {filename}: file not found at {sql_path}", file=sys.stderr)
            rows.append((filename, query_id, "MISSING", "-", "-"))
            continue

        sql = strip_sql_comments(sql_path.read_text())
        if not sql.strip():
            print(f"[skip] {filename}: empty SQL", file=sys.stderr)
            rows.append((filename, query_id, "EMPTY", "-", "-"))
            continue

        # 取 query 文件名 stem 作为 Dune 上的显示名 (去掉 .sql)
        name = sql_path.stem

        if args.dry_run:
            current = read_query(query_id)
            cur_sql = current.get("query_sql", "") if isinstance(current, dict) else ""
            changed = "DIFF" if cur_sql.strip() != sql.strip() else "SAME"
            print(f"[dry-run] {filename} → query {query_id}: {changed} ({len(sql)} chars)")
            rows.append((filename, query_id, changed, "-", "-"))
            continue

        # 真实 PATCH
        try:
            t0 = time.time()
            patch_query(int(query_id), name, sql)
            dt = time.time() - t0
            print(f"[patch]   {filename} → query {query_id}: OK ({dt:.1f}s, {len(sql)} chars)")

            exec_id = "-"
            if args.execute:
                exec_id = execute_query(int(query_id))
                print(f"[exec]    {filename} → execution_id: {exec_id}")
            rows.append((filename, query_id, "OK", exec_id, f"{dt:.1f}s"))
        except Exception as e:
            print(f"[FAIL]    {filename} → query {query_id}: {e}", file=sys.stderr)
            rows.append((filename, query_id, "FAIL", "-", str(e)[:60]))

    # 汇总
    print("\n" + "=" * 78)
    print(f"{'file':<28} {'query_id':<12} {'status':<8} {'execution_id':<20} {'note':<10}")
    print("-" * 78)
    for r in rows:
        print(f"{r[0]:<28} {str(r[1]):<12} {r[2]:<8} {r[3]:<20} {r[4]:<10}")
    print("=" * 78)

    if not args.dry_run:
        ok = sum(1 for r in rows if r[2] == "OK")
        print(f"\n✓ Synced {ok}/{len(rows)} queries")
        if args.execute:
            print(f"  → results will appear in {args.dashboard_url} (usually <60s)")


if __name__ == "__main__":
    main()
