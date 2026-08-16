#!/usr/bin/env python3
"""
RingLPHook 设计合理性验证 — 增强分析
========================================
在现有模拟基础上，补充经济学维度和参数敏感性分析。

核心问题：
1. Fee 收入能否覆盖 IL？
2. 套利者是否还有利润空间？
3. 参数选错时（α 太高/太低）会怎样？
4. 分级 MAX_FEE 真的比固定 MAX_FEE 更好吗？

Usage:
    cd ringlphook/mock
    python analyze_design.py
"""

import os
import sys
import math
import random
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from typing import List, Dict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from simulator import run_simulation, run_single_ema_comparison, PoolState, calc_deviation, calc_exponential_penalty, update_ema
from scenarios import slow_decline, flash_crash, choppy_market, slow_then_crash

random.seed(42)
np.random.seed(42)

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), 'output', 'design_analysis')
os.makedirs(OUTPUT_DIR, exist_ok=True)


def calc_il_percent(price_ratio: float) -> float:
    """无常损失百分比。price_ratio = P_new / P_old。IL% = 2*sqrt(r)/(1+r) - 1"""
    r = price_ratio
    return 2 * math.sqrt(r) / (1 + r) - 1


def calc_arbitrage_profit_space(price_external, price_pool, fee_rate, gas_slippage=0.003):
    """套利者理论利润空间（正 = 有利可图）"""
    if price_pool <= 0:
        return 0.0
    discrepancy = abs(price_external - price_pool) / price_pool
    return discrepancy - (fee_rate + gas_slippage)


def run_enhanced(prices, initial_price=1000.0, tvl=1_000_000.0,
                 alpha_short=0.1, alpha_long=0.01, base_fee=0.0005):
    """增强模拟，返回包含经济学指标的字典"""
    volumes = [random.uniform(500, 2000) for _ in range(len(prices))]
    dual = run_simulation(prices, alpha_short, alpha_long, base_fee, initial_price, volumes)
    single = run_single_ema_comparison(prices, alpha_short, base_fee, initial_price, volumes)

    il = [calc_il_percent(p / initial_price) for p in prices]
    il_usd = [tvl * abs(x) for x in il]

    cf_dual, cf_single = [], []
    cd, cs = 0.0, 0.0
    for rd, rs in zip(dual, single):
        cd += rd.lp_fee_earned
        cs += rs.lp_fee_earned
        cf_dual.append(cd)
        cf_single.append(cs)

    net_dual = [cf_dual[i] - il_usd[i] for i in range(len(prices))]
    net_single = [cf_single[i] - il_usd[i] for i in range(len(prices))]

    arb = []
    for i, r in enumerate(dual):
        if i > 0:
            arb.append(calc_arbitrage_profit_space(prices[i], prices[i-1], r.fee_rate))
        else:
            arb.append(0.0)

    return {
        'prices': prices, 'dual': dual, 'single': single,
        'il_usd': il_usd, 'cf_dual': cf_dual, 'cf_single': cf_single,
        'net_dual': net_dual, 'net_single': net_single,
        'arb': arb, 'tvl': tvl,
    }


def analyze_slow_decline():
    print("\n" + "="*60)
    print("分析 1: 慢速均匀下跌 — 双 EMA 核心验证")
    print("="*60)

    prices = slow_decline(blocks=300, initial_price=1000.0, total_decline=0.02)
    d = run_enhanced(prices, initial_price=1000.0)

    print(f"\n价格: $1000 → ${prices[-1]:.2f} (跌 2%)")
    print(f"IL 损失 (TVL=$1M): ${d['il_usd'][-1]:,.2f}")
    print(f"Single EMA 累计 Fee: ${d['cf_single'][-1]:,.2f}")
    print(f"Dual EMA 累计 Fee:   ${d['cf_dual'][-1]:,.2f}")
    print(f"Single EMA LP 净收益: ${d['net_single'][-1]:,.2f}")
    print(f"Dual EMA LP 净收益:   ${d['net_dual'][-1]:,.2f}")
    imp = ((d['net_dual'][-1] - d['net_single'][-1]) / abs(d['net_single'][-1]) * 100) if d['net_single'][-1] != 0 else 0
    print(f"净收益提升: {imp:+.1f}%")

    fig, axes = plt.subplots(4, 1, figsize=(14, 16))
    fig.suptitle('Slow Decline 2% / 300 blocks: LP Economics', fontsize=14, fontweight='bold')
    b = list(range(1, len(prices)+1))

    axes[0].plot(b, prices, 'k-', label='Price')
    axes[0].plot(b, [r.ema_short for r in d['dual']], 'b-', label='EMA Short', alpha=0.7)
    axes[0].plot(b, [r.ema_long for r in d['dual']], 'g-', label='EMA Long', alpha=0.7)
    axes[0].set_ylabel('Price ($)'); axes[0].legend(); axes[0].grid(True, alpha=0.3)
    axes[0].set_title('Price & EMA')

    axes[1].plot(b, [r.fee_rate*100 for r in d['dual']], 'purple', lw=2, label='Dual EMA')
    axes[1].plot(b, [r.fee_rate*100 for r in d['single']], 'r--', lw=1.5, label='Single EMA')
    axes[1].axhline(y=0.05, color='gray', ls=':', alpha=0.5)
    axes[1].set_ylabel('Fee Rate (%)'); axes[1].legend(); axes[1].grid(True, alpha=0.3)
    axes[1].set_title('Dynamic Fee Rate')

    axes[2].plot(b, d['cf_dual'], 'purple', lw=2, label='Dual EMA Cum Fee')
    axes[2].plot(b, d['cf_single'], 'r--', lw=1.5, label='Single EMA Cum Fee')
    axes[2].plot(b, d['il_usd'], 'orange', lw=2, label='IL (USD)')
    axes[2].fill_between(b, d['il_usd'], alpha=0.1, color='orange')
    axes[2].set_ylabel('USD ($)'); axes[2].legend(); axes[2].grid(True, alpha=0.3)
    axes[2].set_title('Cumulative Fee vs IL')

    axes[3].plot(b, d['net_dual'], 'purple', lw=2, label='Dual EMA Net PnL')
    axes[3].plot(b, d['net_single'], 'r--', lw=1.5, label='Single EMA Net PnL')
    axes[3].axhline(y=0, color='black', lw=0.8)
    axes[3].fill_between(b, d['net_dual'], 0, where=[n > 0 for n in d['net_dual']], alpha=0.2, color='green')
    axes[3].fill_between(b, d['net_dual'], 0, where=[n <= 0 for n in d['net_dual']], alpha=0.2, color='red')
    axes[3].set_ylabel('USD ($)'); axes[3].set_xlabel('Block')
    axes[3].legend(); axes[3].grid(True, alpha=0.3)
    axes[3].set_title('LP Net PnL (Fee - IL)')

    plt.tight_layout()
    p = os.path.join(OUTPUT_DIR, '01_slow_decline_economics.png')
    plt.savefig(p, dpi=150, bbox_inches='tight'); plt.close()
    print(f"\n  Chart: {p}")


def analyze_flash_crash():
    print("\n" + "="*60)
    print("分析 2: 闪崩 10% — Surge 保护验证")
    print("="*60)

    prices = flash_crash(blocks=200, initial_price=1000.0, crash_at=50, crash_percent=0.10)
    d = run_enhanced(prices, initial_price=1000.0)

    surges = [i for i, r in enumerate(d['dual']) if r.surge_triggered]
    print(f"\nSurge 触发 block: {[b+1 for b in surges]}")
    print(f"闪崩瞬间 Fee: {d['dual'][50].fee_rate*100:.2f}%")

    profits = d['arb']
    print(f"套利者最大利润: {max(profits)*100:+.2f}%")
    print(f"套利者平均利润: {sum(profits)/len(profits)*100:+.2f}%")
    profitable = sum(1 for p in profits if p > 0)
    print(f"有利可图 block 数: {profitable}/{len(profits)}")

    fig, axes = plt.subplots(3, 1, figsize=(14, 12))
    fig.suptitle('Flash Crash 10%: Surge & Arbitrage', fontsize=14, fontweight='bold')
    b = list(range(1, len(prices)+1))

    axes[0].plot(b, prices, 'k-', label='Price')
    for sb in surges:
        axes[0].axvline(x=sb+1, color='orange', alpha=0.5, ls=':')
    axes[0].set_ylabel('Price ($)'); axes[0].legend(); axes[0].grid(True, alpha=0.3)
    axes[0].set_title('Price (orange = surge trigger)')

    axes[1].plot(b, [r.fee_rate*100 for r in d['dual']], 'purple', lw=2)
    axes[1].axhline(y=3.0, color='red', ls=':', alpha=0.5)
    axes[1].set_ylabel('Fee Rate (%)'); axes[1].grid(True, alpha=0.3)
    axes[1].set_title('Fee Spike & Decay')

    axes[2].plot(b, [p*100 for p in profits], 'darkred', lw=1.5, label='Arbitrage Profit Space')
    axes[2].axhline(y=0, color='black', lw=0.8)
    axes[2].fill_between(b, [p*100 for p in profits], 0, where=[p > 0 for p in profits], alpha=0.3, color='red')
    axes[2].set_ylabel('Profit (%)'); axes[2].set_xlabel('Block')
    axes[2].legend(); axes[2].grid(True, alpha=0.3)
    axes[2].set_title('Arbitrageur Profit Space (>0 = they win)')

    plt.tight_layout()
    p = os.path.join(OUTPUT_DIR, '02_flash_crash_surge.png')
    plt.savefig(p, dpi=150, bbox_inches='tight'); plt.close()
    print(f"\n  Chart: {p}")


def analyze_sensitivity():
    print("\n" + "="*60)
    print("分析 3: 参数敏感性 alphaShort × alphaLong")
    print("="*60)

    ashorts = [0.05, 0.1, 0.2]
    alongs = [0.005, 0.01, 0.02]
    prices = slow_decline(blocks=300, initial_price=1000.0, total_decline=0.02)

    net_pnl = np.zeros((len(ashorts), len(alongs)))
    avg_fee = np.zeros((len(ashorts), len(alongs)))

    print(f"\n场景: 慢跌 2% / 300 blocks")
    for i, ash in enumerate(ashorts):
        for j, aln in enumerate(alongs):
            d = run_enhanced(prices, alpha_short=ash, alpha_long=aln, initial_price=1000.0)
            net_pnl[i, j] = d['net_dual'][-1]
            avg_fee[i, j] = sum(r.fee_rate for r in d['dual']) / len(d['dual'])
            print(f"  as={ash:.2f}, al={aln:.3f} → Net: ${d['net_dual'][-1]:+8.2f}, AvgFee: {avg_fee[i,j]*100:.3f}%")

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    fig.suptitle('Parameter Sensitivity', fontsize=14, fontweight='bold')

    for idx, (mat, title, cmap) in enumerate([(net_pnl, 'LP Net PnL ($)', 'RdYlGn'),
                                               (avg_fee*100, 'Avg Fee Rate (%)', 'YlOrRd')]):
        ax = axes[idx]
        im = ax.imshow(mat, cmap=cmap, aspect='auto')
        ax.set_xticks(range(len(alongs))); ax.set_yticks(range(len(ashorts)))
        ax.set_xticklabels([f'{a:.3f}' for a in alongs])
        ax.set_yticklabels([f'{a:.2f}' for a in ashorts])
        ax.set_xlabel('alphaLong'); ax.set_ylabel('alphaShort')
        ax.set_title(title)
        for i in range(len(ashorts)):
            for j in range(len(alongs)):
                v = mat[i, j]
                color = 'white' if (idx == 0 and abs(v) > 500) else 'black'
                fmt = f'${v:.0f}' if idx == 0 else f'{v:.3f}%'
                ax.text(j, i, fmt, ha='center', va='center', color=color, fontsize=10)
        plt.colorbar(im, ax=ax)

    plt.tight_layout()
    p = os.path.join(OUTPUT_DIR, '03_param_sensitivity.png')
    plt.savefig(p, dpi=150, bbox_inches='tight'); plt.close()
    print(f"\n  Chart: {p}")

    best = np.unravel_index(np.argmax(net_pnl), net_pnl.shape)
    print(f"\n✅ 最佳参数: alphaShort={ashorts[best[0]]}, alphaLong={alongs[best[1]]}")


def analyze_tiered_maxfee():
    print("\n" + "="*60)
    print("分析 4: 分级 MAX_FEE vs 固定 MAX_FEE")
    print("="*60)

    prices = slow_then_crash(blocks=400, initial_price=1000.0)
    volumes = [random.uniform(500, 2000) for _ in range(len(prices))]

    def run_strategy(max_fee_fn):
        state = PoolState(
            ema_short=1000.0, ema_long=1000.0, alpha_short=0.1, alpha_long=0.01,
            base_fee=0.0005, last_block=0, surge_active=False, last_surge_block=0, net_flow=0.0
        )
        fees = []
        for i, price in enumerate(prices):
            block = i + 1
            update_ema(price, state)
            dev_s = calc_deviation(price, state.ema_short)
            dev_l = calc_deviation(price, state.ema_long)
            dev = max(dev_s, dev_l)
            mult = calc_exponential_penalty(dev)
            fee = state.base_fee * mult
            if dev_s > 0.01:
                state.surge_active = True; state.last_surge_block = block
            if state.surge_active:
                elapsed = block - state.last_surge_block
                surge = 0.03 * math.pow(2, -elapsed / 50)
                fee = max(fee, surge)
                if elapsed > 300: state.surge_active = False
            mf = max_fee_fn(dev)
            fees.append(max(0.0001, min(fee, mf)))
        return fees

    fees_t = run_strategy(lambda dev: 0.03 if dev < 0.02 else (0.015 if dev < 0.05 else 0.01))
    fees_f = run_strategy(lambda dev: 0.03)

    at = sum(fees_t)/len(fees_t); af = sum(fees_f)/len(fees_f)
    print(f"\n分级 MAX_FEE 平均: {at*100:.3f}%")
    print(f"固定 MAX_FEE 平均: {af*100:.3f}%")
    print(f"分级降低: {((at-af)/af*100):+.1f}%")

    fig, axes = plt.subplots(2, 1, figsize=(14, 10))
    fig.suptitle('Tiered vs Fixed MAX_FEE', fontsize=14, fontweight='bold')
    b = list(range(1, len(prices)+1))

    axes[0].plot(b, prices, 'k-'); axes[0].set_ylabel('Price ($)')
    axes[0].grid(True, alpha=0.3); axes[0].set_title('Price Path')

    axes[1].plot(b, [f*100 for f in fees_t], 'purple', lw=2, label='Tiered MAX_FEE')
    axes[1].plot(b, [f*100 for f in fees_f], 'gray', lw=1.5, ls='--', label='Fixed 3%')
    axes[1].set_ylabel('Fee Rate (%)'); axes[1].set_xlabel('Block')
    axes[1].legend(); axes[1].grid(True, alpha=0.3)
    axes[1].set_title('Fee Rate Comparison')

    plt.tight_layout()
    p = os.path.join(OUTPUT_DIR, '04_tiered_vs_fixed.png')
    plt.savefig(p, dpi=150, bbox_inches='tight'); plt.close()
    print(f"\n  Chart: {p}")


def analyze_choppy():
    print("\n" + "="*60)
    print("分析 5: 震荡市场 — 验证不误伤")
    print("="*60)

    prices = choppy_market(blocks=300, initial_price=1000.0, amplitude=0.02, period=50)
    d = run_enhanced(prices, initial_price=1000.0)

    af_dual = sum(r.fee_rate for r in d['dual'])/len(d['dual'])
    af_single = sum(r.fee_rate for r in d['single'])/len(d['single'])
    print(f"\nDual EMA 平均费率: {af_dual*100:.3f}%")
    print(f"Single EMA 平均费率: {af_single*100:.3f}%")
    print(f"fee>0.1% 比例: Dual={sum(1 for r in d['dual'] if r.fee_rate>0.001)/len(prices)*100:.1f}%, "
          f"Single={sum(1 for r in d['single'] if r.fee_rate>0.001)/len(prices)*100:.1f}%")

    fig, axes = plt.subplots(2, 1, figsize=(14, 8))
    fig.suptitle('Choppy Market: Overreaction Test', fontsize=14, fontweight='bold')
    b = list(range(1, len(prices)+1))

    axes[0].plot(b, prices, 'k-'); axes[0].set_ylabel('Price ($)')
    axes[0].grid(True, alpha=0.3); axes[0].set_title('Price: ±2% Oscillation')

    axes[1].plot(b, [r.fee_rate*100 for r in d['dual']], 'purple', lw=2, label='Dual EMA')
    axes[1].plot(b, [r.fee_rate*100 for r in d['single']], 'r--', lw=1.5, label='Single EMA')
    axes[1].axhline(y=0.05, color='gray', ls=':', alpha=0.5)
    axes[1].set_ylabel('Fee Rate (%)'); axes[1].set_xlabel('Block')
    axes[1].legend(); axes[1].grid(True, alpha=0.3)
    axes[1].set_title('Fee Should Stay Near Base')

    plt.tight_layout()
    p = os.path.join(OUTPUT_DIR, '05_choppy_overreaction.png')
    plt.savefig(p, dpi=150, bbox_inches='tight'); plt.close()
    print(f"\n  Chart: {p}")


def main():
    print("=" * 60)
    print("RingLPHook 设计合理性验证")
    print("=" * 60)
    print(f"\n输出目录: {OUTPUT_DIR}")

    analyze_slow_decline()
    analyze_flash_crash()
    analyze_sensitivity()
    analyze_tiered_maxfee()
    analyze_choppy()

    print("\n" + "=" * 60)
    print("全部分析完成!")
    print(f"图表目录: {OUTPUT_DIR}")
    print("=" * 60)


if __name__ == '__main__':
    main()
