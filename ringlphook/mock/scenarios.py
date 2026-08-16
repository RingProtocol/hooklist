"""
Scenario Definitions
====================
Define price series for various market scenarios to test RingLPHook EMA behavior.
"""

import random
import math
from typing import List


# ============ Scenario 1: Normal Fluctuation ============
def normal_fluctuation(
    blocks: int = 300,
    initial_price: float = 1000.0,
    volatility: float = 0.002
) -> List[float]:
    """
    Normal random walk, no trend.
    Simulates: ETH fluctuating around $1000
    """
    prices = [initial_price]
    for _ in range(blocks - 1):
        change = random.gauss(0, volatility)
        new_price = prices[-1] * (1 + change)
        prices.append(new_price)
    return prices


# ============ Scenario 2: Slow Decline (Core Test) ============
def slow_decline(
    blocks: int = 300,
    initial_price: float = 1000.0,
    total_decline: float = 0.02
) -> List[float]:
    """
    Slow steady decline: 2% drop over 1 hour (300 blocks)
    ~0.0067% per block.

    This is the core test for Dual EMA.
    """
    prices = []
    per_block_decline = total_decline / blocks
    for i in range(blocks):
        price = initial_price * (1 - per_block_decline * i)
        # 加入极小噪音，更真实
        noise = random.gauss(0, 0.0001)
        price *= (1 + noise)
        prices.append(price)
    return prices


# ============ Scenario 3: Slow Rise ============
def slow_rise(
    blocks: int = 300,
    initial_price: float = 1000.0,
    total_rise: float = 0.02
) -> List[float]:
    """
    Slow steady rise: 2% increase over 1 hour.
    Tests Dual EMA response to slow rises (symmetric to slow decline).
    """
    prices = []
    per_block_rise = total_rise / blocks
    for i in range(blocks):
        price = initial_price * (1 + per_block_rise * i)
        noise = random.gauss(0, 0.0001)
        price *= (1 + noise)
        prices.append(price)
    return prices


# ============ Scenario 4: Flash Crash ============
def flash_crash(
    blocks: int = 200,
    initial_price: float = 1000.0,
    crash_at: int = 50,
    crash_percent: float = 0.10
) -> List[float]:
    """
    Flash crash: normal for 50 blocks, then instant 10% drop at block 51.
    Tests surge protection.
    """
    prices = []
    for i in range(blocks):
        if i < crash_at:
            # 正常波动
            noise = random.gauss(0, 0.001)
            price = initial_price * (1 + noise)
        elif i == crash_at:
            # 瞬间砸盘
            price = initial_price * (1 - crash_percent)
        else:
            # 缓慢恢复
            recovery = (i - crash_at) / 100
            price = initial_price * (1 - crash_percent + recovery * crash_percent * 0.5)
            noise = random.gauss(0, 0.001)
            price *= (1 + noise)
        prices.append(price)
    return prices


# ============ Scenario 5: Slow Decline + Flash Crash ============
def slow_then_crash(
    blocks: int = 400,
    initial_price: float = 1000.0
) -> List[float]:
    """
    Slow decline 1%, then instant crash 8%, then recovery.
    Tests Dual EMA + surge combined protection.
    """
    prices = []
    for i in range(blocks):
        if i < 150:
            # 慢跌 1%
            price = initial_price * (1 - 0.01 * i / 150)
        elif i == 150:
            # 瞬间再跌 8%
            price = initial_price * 0.99 * 0.92
        else:
            # 缓慢恢复
            recovery = (i - 150) / 200
            price = initial_price * 0.99 * 0.92 * (1 + recovery * 0.05)
        noise = random.gauss(0, 0.0005)
        price *= (1 + noise)
        prices.append(price)
    return prices


# ============ Scenario 6: Choppy Market ============
def choppy_market(
    blocks: int = 300,
    initial_price: float = 1000.0,
    amplitude: float = 0.02,
    period: int = 50
) -> List[float]:
    """
    Choppy market: price oscillates within a range.
    Tests if EMA overreacts to noise.
    """
    prices = []
    for i in range(blocks):
        # 正弦波 + 噪音
        trend = math.sin(i / period * 2 * math.pi) * amplitude
        noise = random.gauss(0, 0.001)
        price = initial_price * (1 + trend + noise)
        prices.append(price)
    return prices


# ============ Scenario 7: V Recovery ============
def v_recovery(
    blocks: int = 300,
    initial_price: float = 1000.0
) -> List[float]:
    """
    V-shaped recovery: drop 5%, then rapid recovery.
    Tests fee decay after surge trigger.
    """
    prices = []
    for i in range(blocks):
        if i < 100:
            # 跌 5%
            price = initial_price * (1 - 0.05 * i / 100)
        else:
            # 恢复
            recovery = (i - 100) / 200
            price = initial_price * 0.95 * (1 + recovery * 0.06)
        noise = random.gauss(0, 0.0005)
        price *= (1 + noise)
        prices.append(price)
    return prices


# ============ All Scenarios ============
ALL_SCENARIOS = {
    "01_normal_fluctuation": normal_fluctuation,
    "02_slow_decline_2pct": slow_decline,
    "03_slow_rise_2pct": slow_rise,
    "04_flash_crash_10pct": flash_crash,
    "05_slow_then_crash": slow_then_crash,
    "06_choppy_market": choppy_market,
    "07_v_recovery": v_recovery,
}


def get_scenario(name: str, **kwargs):
    """Get price series for a named scenario."""
    if name not in ALL_SCENARIOS:
        raise ValueError(f"Unknown scenario: {name}. Available: {list(ALL_SCENARIOS.keys())}")
    return ALL_SCENARIOS[name](**kwargs)
