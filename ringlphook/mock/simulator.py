"""
RingLPHook EMA 双引擎模拟器
===========================
模拟不同市场场景下，单 EMA vs 双 EMA 的 fee 表现。
"""

import math
import random
from dataclasses import dataclass
from typing import List, Tuple


@dataclass
class PoolState:
    """Pool 状态，对应合约中的 storage"""
    ema_short: float
    ema_long: float
    alpha_short: float
    alpha_long: float
    base_fee: float      # 0.05% = 0.0005
    last_block: int
    surge_active: bool
    last_surge_block: int
    net_flow: float


@dataclass
class SwapResult:
    """单次 swap 的结果"""
    block: int
    price: float
    ema_short: float
    ema_long: float
    dev_short: float
    dev_long: float
    deviation: float
    fee_rate: float
    surge_triggered: bool
    lp_fee_earned: float
    swap_volume: float


def calc_deviation(current: float, ema: float) -> float:
    """计算偏离度 = |current - ema| / ema"""
    if ema == 0:
        return 0
    return abs(current - ema) / ema


def calc_exponential_penalty(deviation: float, alpha: float = 10.0) -> float:
    """
    指数惩罚函数: multiplier = e^(ALPHA * deviation)
    alpha = 10 时:
    - deviation 1%  -> multiplier ≈ 1.105
    - deviation 5%  -> multiplier ≈ 1.649
    - deviation 10% -> multiplier ≈ 2.718
    """
    return math.exp(alpha * deviation)


def calc_fee(
    price: float,
    state: PoolState,
    block: int,
    is_buy: bool = True,
    swap_volume: float = 1000.0
) -> Tuple[float, bool]:
    """
    计算当前 fee，返回 (fee_rate, surge_triggered)
    """
    # 1. 双 EMA 偏离度
    dev_short = calc_deviation(price, state.ema_short)
    dev_long = calc_deviation(price, state.ema_long)
    deviation = max(dev_short, dev_long)

    # 2. 指数惩罚
    multiplier = calc_exponential_penalty(deviation)
    dynamic_fee = state.base_fee * multiplier

    # 3. Surge 检测（用 ema_short 检测瞬间偏离）
    surge_triggered = False
    surge_threshold = 0.01  # 1%
    max_surge_fee = 0.03    # 3%
    surge_half_life = 50    # blocks

    if dev_short > surge_threshold:
        state.surge_active = True
        state.last_surge_block = block
        surge_triggered = True

    # Surge 衰减
    if state.surge_active:
        elapsed = block - state.last_surge_block
        # 指数衰减: surge_fee * 2^(-elapsed / half_life)
        decay = math.pow(2, -elapsed / surge_half_life)
        surge_fee = max_surge_fee * decay
        dynamic_fee = max(dynamic_fee, surge_fee)

        # 自动结束 surge
        if elapsed > 300:  # 300 blocks
            state.surge_active = False

    # 4. Clamp
    min_fee = 0.0001  # 0.01%
    max_fee = 0.03     # 3%
    fee_rate = max(min_fee, min(dynamic_fee, max_fee))

    # 5. 方向性调节（简化版）
    if not is_buy and state.net_flow < 0:
        fee_rate *= 1.5
        fee_rate = min(fee_rate, max_fee)

    # 6. LP 收益 = volume * fee_rate
    lp_fee_earned = swap_volume * fee_rate

    return fee_rate, surge_triggered, lp_fee_earned


def update_ema(price: float, state: PoolState) -> None:
    """更新双 EMA"""
    # 短周期 EMA
    state.ema_short = state.alpha_short * price + (1 - state.alpha_short) * state.ema_short
    # 长周期 EMA
    state.ema_long = state.alpha_long * price + (1 - state.alpha_long) * state.ema_long


def run_simulation(
    prices: List[float],
    alpha_short: float = 0.1,
    alpha_long: float = 0.01,
    base_fee: float = 0.0005,
    initial_price: float = 1000.0,
    volumes: List[float] = None
) -> List[SwapResult]:
    """
    运行完整模拟，给定价格序列，返回每 block 的结果。
    
    Args:
        prices: 每 block 的价格列表
        alpha_short: 短周期 EMA 平滑因子 (0.1 = 1e17 in solidity)
        alpha_long: 长周期 EMA 平滑因子 (0.01 = 1e16 in solidity)
        base_fee: 基础费率 (0.0005 = 0.05%)
        initial_price: 初始价格
        volumes: 每 block 的交易量列表（可选，默认 $1000）
    """
    if volumes is None:
        volumes = [1000.0] * len(prices)

    state = PoolState(
        ema_short=initial_price,
        ema_long=initial_price,
        alpha_short=alpha_short,
        alpha_long=alpha_long,
        base_fee=base_fee,
        last_block=0,
        surge_active=False,
        last_surge_block=0,
        net_flow=0.0
    )

    results = []

    for i, price in enumerate(prices):
        block = i + 1

        # 更新 EMA（模拟 afterSwap）
        update_ema(price, state)

        # 计算 fee（模拟 beforeSwap）
        # 假设交替 buy/sell
        is_buy = (i % 2 == 0)
        fee_rate, surge_triggered, lp_fee = calc_fee(price, state, block, is_buy, volumes[i])

        results.append(SwapResult(
            block=block,
            price=price,
            ema_short=state.ema_short,
            ema_long=state.ema_long,
            dev_short=calc_deviation(price, state.ema_short),
            dev_long=calc_deviation(price, state.ema_long),
            deviation=max(calc_deviation(price, state.ema_short), calc_deviation(price, state.ema_long)),
            fee_rate=fee_rate,
            surge_triggered=surge_triggered,
            lp_fee_earned=lp_fee,
            swap_volume=volumes[i]
        ))

    return results


def run_single_ema_comparison(
    prices: List[float],
    alpha: float = 0.1,
    base_fee: float = 0.0005,
    initial_price: float = 1000.0,
    volumes: List[float] = None
) -> List[SwapResult]:
    """
    用单 EMA 跑同样的价格序列，用于对比。
    """
    if volumes is None:
        volumes = [1000.0] * len(prices)

    ema = initial_price
    surge_active = False
    last_surge_block = 0
    results = []

    for i, price in enumerate(prices):
        block = i + 1

        # 更新单 EMA
        ema = alpha * price + (1 - alpha) * ema

        # 偏离度
        deviation = calc_deviation(price, ema)

        # 指数惩罚
        multiplier = calc_exponential_penalty(deviation)
        dynamic_fee = base_fee * multiplier

        # Surge（简化）
        surge_threshold = 0.01
        max_surge_fee = 0.03
        surge_half_life = 50
        surge_triggered = False

        if deviation > surge_threshold:
            surge_active = True
            last_surge_block = block
            surge_triggered = True

        if surge_active:
            elapsed = block - last_surge_block
            decay = math.pow(2, -elapsed / surge_half_life)
            surge_fee = max_surge_fee * decay
            dynamic_fee = max(dynamic_fee, surge_fee)
            if elapsed > 300:
                surge_active = False

        # Clamp
        fee_rate = max(0.0001, min(dynamic_fee, 0.03))

        results.append(SwapResult(
            block=block,
            price=price,
            ema_short=ema,
            ema_long=ema,  # 单 EMA 时两者相同
            dev_short=deviation,
            dev_long=deviation,
            deviation=deviation,
            fee_rate=fee_rate,
            surge_triggered=surge_triggered,
            lp_fee_earned=volumes[i] * fee_rate,
            swap_volume=volumes[i]
        ))

    return results
