#!/usr/bin/env python3
"""
Dune API runner: execute SQL, poll for results, print as table.
Usage: python3 scripts/dune_run.py <sql-file> [part-name]
"""
import os
import sys
import time
import json
import requests
from pathlib import Path

# Load .env manually
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


def run_sql(sql: str, name: str = "ad-hoc"):
    """Execute raw SQL, poll until done, return rows + meta."""
    r = requests.post(
        f"{BASE}/sql/execute",
        headers=HEADERS,
        json={"sql": sql, "name": name, "performance": "medium"},
        timeout=60,
    )
    r.raise_for_status()
    exec_id = r.json()["execution_id"]
    print(f"[{name}] execution_id: {exec_id}", file=sys.stderr)

    for i in range(60):  # up to 5 min
        rr = requests.get(
            f"{BASE}/execution/{exec_id}/results",
            headers=HEADERS,
            params={"limit": 5000},
            timeout=60,
        )
        rr.raise_for_status()
        body = rr.json()
        state = body.get("state", "")
        if state in ("QUERY_STATE_COMPLETED", "QUERY_STATE_FAILED", "QUERY_STATE_CANCELLED"):
            if state != "QUERY_STATE_COMPLETED":
                print(json.dumps(body, indent=2, ensure_ascii=False)[:2000], file=sys.stderr)
                sys.exit(2)
            return body
        time.sleep(5)
    print("timeout", file=sys.stderr)
    sys.exit(3)


def print_table(body):
    table = format_table(body)
    print(table)
    return table


def format_table(body):
    rows = body.get("result", {}).get("rows", [])
    cols = body.get("result", {}).get("metadata", {}).get("columns", [])
    if not rows:
        return "(no rows)"
    names = [c["name"] if isinstance(c, dict) else c for c in cols]
    if not names and rows:
        names = list(rows[0].keys())

    def s(v):
        if v is None:
            return ""
        if isinstance(v, float):
            return f"{v:.6g}" if abs(v) < 1e-3 or v != int(v) else f"{int(v)}"
        sv = str(v)
        return sv[:60] + "…" if len(sv) > 60 else sv

    widths = [max(len(n), max((len(s(r.get(n))) for r in rows), default=0)) for n in names]
    lines = [
        " | ".join(n.ljust(w) for n, w in zip(names, widths)),
        "-+-".join("-" * w for w in widths),
    ]
    lines += [
        " | ".join(s(r.get(n)).ljust(w) for n, w in zip(names, widths))
        for r in rows
    ]
    lines.append(f"[{len(rows)} rows, took {body.get('result', {}).get('metadata', {}).get('duration', '?')}s]")
    return "\n".join(lines)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: dune_run.py <sql-file> [part-name] [--save]", file=sys.stderr)
        sys.exit(1)
    args = sys.argv[1:]
    save = "--save" in args
    args = [a for a in args if a != "--save"]
    if not args:
        print("usage: dune_run.py <sql-file> [part-name] [--save]", file=sys.stderr)
        sys.exit(1)
    sql_path = Path(args[0])
    part_name = args[1] if len(args) > 1 else sql_path.stem
    sql = sql_path.read_text()
    # strip -- comment lines for cleaner execution
    cleaned = "\n".join(
        line for line in sql.splitlines()
        if not line.strip().startswith("--")
    )
    body = run_sql(cleaned, name=part_name)
    table = format_table(body)
    print(table)
    if save:
        out = sql_path.with_suffix("").with_name(sql_path.stem + ".result.md")
        out.write_text(
            f"# {part_name}\n\n"
            f"Source: `{sql_path.name}`  |  "
            f"execution_id: `{body.get('execution_id','?')}`  |  "
            f"state: `{body.get('state','?')}`\n\n"
            f"```\n{table}\n```\n"
        )
        print(f"\n[saved → {out}]", file=sys.stderr)
