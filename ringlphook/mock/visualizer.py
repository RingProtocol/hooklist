"""
Visualizer
==========
Generate charts from simulation results to show Dual EMA effects.
"""

import os
from typing import List, Dict
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from simulator import SwapResult


def plot_scenario(
    results_dual: List[SwapResult],
    results_single: List[SwapResult],
    scenario_name: str,
    save_path: str = None
) -> str:
    """
    Plot full comparison chart for a single scenario (Dual EMA vs Single EMA).
    Returns saved file path.
    """
    fig, axes = plt.subplots(3, 1, figsize=(14, 12))
    fig.suptitle(f'{scenario_name}: Dual EMA vs Single EMA', fontsize=14, fontweight='bold')

    blocks = [r.block for r in results_dual]
    prices = [r.price for r in results_dual]

    # ===== 图 1: 价格 + EMA 曲线 =====
    ax1 = axes[0]
    ax1.plot(blocks, prices, label='Actual Price', color='black', linewidth=1.5, alpha=0.8)
    ax1.plot(blocks, [r.ema_short for r in results_dual], label='Dual EMA (Short)', color='blue', linewidth=2)
    ax1.plot(blocks, [r.ema_long for r in results_dual], label='Dual EMA (Long)', color='green', linewidth=2)
    ax1.plot(blocks, [r.ema_short for r in results_single], label='Single EMA', color='red', linewidth=2, linestyle='--')

    # Mark surge triggers
    surge_blocks = [r.block for r in results_dual if r.surge_triggered]
    if surge_blocks:
        for sb in surge_blocks:
            ax1.axvline(x=sb, color='orange', alpha=0.3, linestyle=':')
        ax1.axvline(x=0, color='orange', alpha=0.3, linestyle=':', label='Surge Triggered')

    ax1.set_ylabel('Price ($)')
    ax1.legend(loc='best')
    ax1.grid(True, alpha=0.3)
    ax1.set_title('Price & EMA Trend')

    # ===== 图 2: 偏离度 =====
    ax2 = axes[1]
    ax2.plot(blocks, [r.dev_short * 100 for r in results_dual], label='Dual EMA devShort', color='blue')
    ax2.plot(blocks, [r.dev_long * 100 for r in results_dual], label='Dual EMA devLong', color='green')
    ax2.plot(blocks, [r.deviation * 100 for r in results_dual], label='Dual EMA Final Deviation (max)', color='purple', linewidth=2)
    ax2.plot(blocks, [r.deviation * 100 for r in results_single], label='Single EMA Deviation', color='red', linestyle='--')

    # Surge threshold line
    ax2.axhline(y=1.0, color='orange', linestyle='--', alpha=0.5, label='Surge Threshold (1%)')

    ax2.set_ylabel('Deviation (%)')
    ax2.legend(loc='best')
    ax2.grid(True, alpha=0.3)
    ax2.set_title('Price Deviation Comparison')

    # ===== 图 3: Fee 费率 =====
    ax3 = axes[2]
    fees_dual = [r.fee_rate * 100 for r in results_dual]
    fees_single = [r.fee_rate * 100 for r in results_single]
    ax3.plot(blocks, fees_dual, label='Dual EMA Fee', color='purple', linewidth=2)
    ax3.plot(blocks, fees_single, label='Single EMA Fee', color='red', linestyle='--')

    # Mark base/max fee
    ax3.axhline(y=0.05, color='gray', linestyle=':', alpha=0.5, label='Base Fee (0.05%)')
    ax3.axhline(y=3.0, color='red', linestyle=':', alpha=0.5, label='Max Fee (3%)')

    ax3.set_ylabel('Fee Rate (%)')
    ax3.set_xlabel('Block')
    ax3.legend(loc='best')
    ax3.grid(True, alpha=0.3)
    ax3.set_title('Dynamic Fee Rate Comparison')

    plt.tight_layout()

    if save_path:
        os.makedirs(os.path.dirname(save_path) or '.', exist_ok=True)
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        print(f"  Chart saved: {save_path}")

    plt.close()
    return save_path


def plot_fee_comparison_bar(
    scenario_stats: Dict[str, Dict],
    save_path: str = None
) -> str:
    """
    Plot bar chart comparing avg fee across all scenarios.
    """
    scenarios = list(scenario_stats.keys())
    avg_fees_dual = [scenario_stats[s]['avg_fee_dual'] * 100 for s in scenarios]
    avg_fees_single = [scenario_stats[s]['avg_fee_single'] * 100 for s in scenarios]
    total_fees_dual = [scenario_stats[s]['total_fee_dual'] for s in scenarios]
    total_fees_single = [scenario_stats[s]['total_fee_single'] for s in scenarios]

    fig, axes = plt.subplots(1, 2, figsize=(16, 6))
    fig.suptitle('All Scenarios: Single EMA vs Dual EMA Comparison', fontsize=14, fontweight='bold')

    # Average fee rate
    ax1 = axes[0]
    x = range(len(scenarios))
    width = 0.35
    ax1.bar([i - width/2 for i in x], avg_fees_single, width, label='Single EMA', color='red', alpha=0.7)
    ax1.bar([i + width/2 for i in x], avg_fees_dual, width, label='Dual EMA', color='purple', alpha=0.7)
    ax1.set_ylabel('Avg Fee Rate (%)')
    ax1.set_xticks(x)
    ax1.set_xticklabels(scenarios, rotation=45, ha='right')
    ax1.legend()
    ax1.grid(True, alpha=0.3, axis='y')
    ax1.set_title('Average Fee Rate Comparison')

    # Total LP revenue
    ax2 = axes[1]
    ax2.bar([i - width/2 for i in x], total_fees_single, width, label='Single EMA', color='red', alpha=0.7)
    ax2.bar([i + width/2 for i in x], total_fees_dual, width, label='Dual EMA', color='purple', alpha=0.7)
    ax2.set_ylabel('Total LP Fee Revenue ($)')
    ax2.set_xticks(x)
    ax2.set_xticklabels(scenarios, rotation=45, ha='right')
    ax2.legend()
    ax2.grid(True, alpha=0.3, axis='y')
    ax2.set_title('Total LP Fee Revenue Comparison')

    plt.tight_layout()

    if save_path:
        os.makedirs(os.path.dirname(save_path) or '.', exist_ok=True)
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        print(f"  Summary chart saved: {save_path}")

    plt.close()
    return save_path


def generate_summary_text(
    scenario_name: str,
    results_dual: List[SwapResult],
    results_single: List[SwapResult]
) -> str:
    """Generate text summary for a scenario."""
    avg_fee_dual = sum(r.fee_rate for r in results_dual) / len(results_dual)
    avg_fee_single = sum(r.fee_rate for r in results_single) / len(results_single)
    total_fee_dual = sum(r.lp_fee_earned for r in results_dual)
    total_fee_single = sum(r.lp_fee_earned for r in results_single)
    max_fee_dual = max(r.fee_rate for r in results_dual)
    max_fee_single = max(r.fee_rate for r in results_single)
    surge_count_dual = sum(1 for r in results_dual if r.surge_triggered)
    surge_count_single = sum(1 for r in results_single if r.surge_triggered)

    improvement = ((total_fee_dual - total_fee_single) / total_fee_single * 100) if total_fee_single > 0 else 0

    return f"""
### {scenario_name}

| Metric | Single EMA | Dual EMA | Improvement |
|---|---|---|---|
| Avg Fee Rate | {avg_fee_single*100:.3f}% | {avg_fee_dual*100:.3f}% | {(avg_fee_dual/avg_fee_single-1)*100:+.1f}% |
| Max Fee Rate | {max_fee_single*100:.3f}% | {max_fee_dual*100:.3f}% | - |
| Total LP Revenue | ${total_fee_single:.2f} | ${total_fee_dual:.2f} | **+{improvement:.1f}%** |
| Surge Triggers | {surge_count_single} | {surge_count_dual} | - |
"""
