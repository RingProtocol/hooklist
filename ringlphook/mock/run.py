#!/usr/bin/env python3
"""
RingLPHook Dual EMA Simulator Runner
=====================================
Run all scenarios and generate charts + HTML report.

Usage:
    cd ringlphook/mock
    python run.py

Output:
    output/ directory with all charts and report.html
"""

import os
import sys
from datetime import datetime
from typing import List

# Ensure local modules can be found
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from simulator import run_simulation, run_single_ema_comparison
from scenarios import ALL_SCENARIOS
from visualizer import plot_scenario, plot_fee_comparison_bar, generate_summary_text


def main():
    print("=" * 60)
    print("RingLPHook Dual EMA Simulator")
    print("=" * 60)
    print()

    # 输出目录
    output_dir = os.path.join(os.path.dirname(__file__), 'output')
    os.makedirs(output_dir, exist_ok=True)

    # 收集统计数据
    stats = {}
    summary_sections = []

    # 参数设置（与文档一致）
    alpha_short = 0.1      # 1e17 in solidity
    alpha_long = 0.01     # 1e16 in solidity
    base_fee = 0.0005     # 0.05%
    initial_price = 1000.0

    print(f"Parameters:")
    print(f"  alphaShort = {alpha_short} (short-term EMA)")
    print(f"  alphaLong  = {alpha_long} (long-term EMA)")
    print(f"  baseFee    = {base_fee*100}%")
    print(f"  initialPrice = ${initial_price}")
    print()

    for scenario_name, scenario_fn in ALL_SCENARIOS.items():
        print(f"Running: {scenario_name}")

        # 生成价格序列
        prices = scenario_fn(initial_price=initial_price)
        volumes = [random_volume(i) for i in range(len(prices))]

        # 双 EMA 模拟
        results_dual = run_simulation(
            prices=prices,
            alpha_short=alpha_short,
            alpha_long=alpha_long,
            base_fee=base_fee,
            initial_price=initial_price,
            volumes=volumes
        )

        # 单 EMA 模拟（对比用）
        results_single = run_single_ema_comparison(
            prices=prices,
            alpha=alpha_short,
            base_fee=base_fee,
            initial_price=initial_price,
            volumes=volumes
        )

        # 统计
        avg_fee_dual = sum(r.fee_rate for r in results_dual) / len(results_dual)
        avg_fee_single = sum(r.fee_rate for r in results_single) / len(results_single)
        total_fee_dual = sum(r.lp_fee_earned for r in results_dual)
        total_fee_single = sum(r.lp_fee_earned for r in results_single)

        stats[scenario_name] = {
            'avg_fee_dual': avg_fee_dual,
            'avg_fee_single': avg_fee_single,
            'total_fee_dual': total_fee_dual,
            'total_fee_single': total_fee_single,
        }

        # 生成图表
        img_path = os.path.join(output_dir, f'{scenario_name}.png')
        plot_scenario(results_dual, results_single, scenario_name, save_path=img_path)

        # 生成文字摘要
        summary = generate_summary_text(scenario_name, results_dual, results_single)
        summary_sections.append(summary)
        print(summary)
        print()

    # Generate summary chart
    print("Generating summary chart...")
    bar_path = os.path.join(output_dir, '00_summary_comparison.png')
    plot_fee_comparison_bar(stats, save_path=bar_path)

    # Generate HTML report
    print("Generating HTML report...")
    report_path = os.path.join(output_dir, 'report.html')
    generate_html_report(report_path, summary_sections, list(ALL_SCENARIOS.keys()))

    print()
    print("=" * 60)
    print("Simulation Complete!")
    print(f"Output dir: {output_dir}")
    print(f"HTML report: {report_path}")
    print()
    print("Open report.html in browser to see full report")
    print("=" * 60)


def random_volume(block_idx: int) -> float:
    """Generate random trade volume."""
    import random
    base = random.uniform(500, 2000)
    return base


def generate_html_report(path: str, summaries: List[str], scenario_names: List[str]):
    """Generate HTML report"""
    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>RingLPHook EMA Simulation Report</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; margin: 40px; background: #f5f5f5; }}
        .container {{ max-width: 1200px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }}
        h1 {{ color: #1a1a2e; border-bottom: 3px solid #16213e; padding-bottom: 10px; }}
        h2 {{ color: #16213e; margin-top: 40px; border-left: 4px solid #e94560; padding-left: 12px; }}
        h3 {{ color: #0f3460; }}
        .summary {{ background: #f8f9fa; padding: 20px; border-radius: 6px; margin: 20px 0; }}
        table {{ border-collapse: collapse; width: 100%; margin: 15px 0; }}
        th, td {{ border: 1px solid #ddd; padding: 10px; text-align: center; }}
        th {{ background: #16213e; color: white; }}
        tr:nth-child(even) {{ background: #f2f2f2; }}
        .highlight {{ background: #fff3cd; font-weight: bold; }}
        img {{ max-width: 100%; border: 1px solid #ddd; border-radius: 4px; margin: 20px 0; }}
        .footer {{ margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px; text-align: center; }}
        .intro {{ background: #e8f4f8; padding: 20px; border-radius: 6px; margin-bottom: 30px; }}
        .intro h3 {{ margin-top: 0; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>RingLPHook Dual EMA Simulation Report</h1>
        <p style="color: #666;">Generated: {now}</p>

        <div class="intro">
            <h3>What is this report?</h3>
            <p>This report shows RingLPHook's <strong>Dual EMA dynamic fee mechanism</strong> across different market scenarios via simulation.</p>
            <p>Each scenario compares:</p>
            <ul>
                <li><strong>Dual EMA (purple/green)</strong>: Our approach - short + long EMA, take max deviation</li>
                <li><strong>Single EMA (red dashed)</strong>: Baseline - only short EMA</li>
            </ul>
            <p><strong>Key takeaway</strong>: In "slow decline" scenarios, Dual EMA fee (purple) should be much higher than Single EMA (red), meaning LP earns more fees to offset impermanent loss.</p>
        </div>

        <h2>Summary Comparison</h2>
        <img src="00_summary_comparison.png" alt="Summary">

        <h2>Detailed Scenario Analysis</h2>
"""

    for i, name in enumerate(scenario_names):
        summary = summaries[i]
        img_name = f"{name}.png"
        html += f"""
        <h3>Scenario {i+1}: {name}</h3>
        <div class="summary">
            {summary.replace(chr(10), '<br>')}
        </div>
        <img src="{img_name}" alt="{name}">
        <hr>
"""

    html += """
        <h2>Core Formula Reference</h2>
        <div class="summary">
            <h3>Dual EMA Update</h3>
            <pre>
emaShort = alpha_short * currentPrice + (1 - alpha_short) * emaShort
emaLong  = alpha_long  * currentPrice + (1 - alpha_long)  * emaLong
            </pre>
            <p>alpha_short = 0.1 (fast reaction), alpha_long = 0.01 (slow, more lag)</p>

            <h3>Deviation Calculation</h3>
            <pre>
devShort = |current - emaShort| / emaShort
devLong  = |current - emaLong|  / emaLong
deviation = max(devShort, devLong)
            </pre>

            <h3>Fee Calculation</h3>
            <pre>
fee = baseFee * e^(10 * deviation)
if deviation > 1%: surge triggers, fee caps at 3%
            </pre>

            <h3>Why Dual EMA is better?</h3>
            <p>During <strong>slow steady decline</strong>, short EMA follows price → devShort ~ 0 → fee stays low.</p>
            <p>But <strong>long EMA lags significantly</strong> → devLarge is large → fee rises sharply → LP gets compensated.</p>
        </div>

        <div class="footer">
            <p>RingLPHook Simulator | Ring Protocol | For research purposes only</p>
        </div>
    </div>
</body>
</html>
"""

    with open(path, 'w', encoding='utf-8') as f:
        f.write(html)


if __name__ == '__main__':
    main()
