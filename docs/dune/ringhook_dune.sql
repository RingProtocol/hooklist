-- =============================================================
-- Ring Protocol Hooks 监控 (Ethereum Mainnet)
-- 关联数据源:
--   - Pool 元信息:    dune.uniswap_fnd.result_uniswap_v_4_all_pools_data
--   - Pool Liquidity: uniswap_v4_ethereum.PoolManager_evt_ModifyLiquidity
--   - Swap 数据:      dex.trades
-- 数据时间: NOW() - 30d / 7d
--
-- 说明:
--   - p.pool  = 32 字节 pool_id (keccak256 哈希)
--   - p.hooks = 20 字节 hook 地址
--   - t.maker = 32 字节 pool_id (与 p.pool 同源)
--   - liquidity = 该 pool 所有 ModifyLiquidity 事件的 liquidityDelta 之和
--                 (v4 净变化, 可近似视为当前活跃流动性; 严格意义上 pool 活跃流动性
--                  还要按当前 tick 过滤, 这里是粗估)
--   - fee_in_percent = pool 静态费率 (Ring FewToken 池全部 = 0, 因为 wrap/unwrap 1:1)
--   - total_fees_30d / 7d = 静态费率 * volume, 因 fee_in_percent=0 会 NULL
--                          (Ring 的实际费率在 hook beforeSwap/afterSwap 逻辑里,
--                           要从 hook 合约单独算, 这里不覆盖)
-- =============================================================

WITH ring_hooks AS (
    SELECT * FROM (VALUES
        ('FewETHHook',    0x044301939deb7ca53c4733dd4d9b3bc5ea0c6888),
        ('FewUNIHook',    0x4b3e2a8cf36c7eb0fba2a5b39b20c896c6f22888),
        ('FewWBTCHook',   0x0fe942afdb2f51e25cbf892aad175c6a574f2888),
        ('FewUSDCHook',   0x4b2eb653d13e6c9ac5a0a01fde22f2c8d6592888),
        ('FewDAIHook',    0x85b648a64aed6307d5d5ce26e6ae086c17bde888),
        ('FewUSDTHook',   0xbadf77d50478b4432ef1f243b9c0bc7869486888),
        ('FewCBBTCHook',  0x8347b7a3807c681513d2b51b8223e59aa16a2888),
        ('FewweETHHook',  0x877323adbf747f85eb8d182d42f01f34a5492888),
        ('FewwstETHHook', 0x75ae0292e8ad3ab60b9a1a7b3046d3f4abdfa888)
    ) AS t(hook_name, hook_address)
),

-- Step 1: 找出 Ring hooks 对应的 v4 pools (含 fee / tick 等元信息)
ring_pools AS (
    SELECT
        p.pool,
        p.hooks,
        p.fee_in_percent,
        p.pair,
        p.token0_symbol,
        p.token1_symbol,
        p.token0_address,
        p.token1_address,
        p.tick           AS current_tick,
        p.tickspacing,
        p.created_time
    FROM dune.uniswap_fnd.result_uniswap_v_4_all_pools_data p
    INNER JOIN ring_hooks rh
        ON p.hooks = rh.hook_address
    WHERE p.blockchain = 'ethereum'
),

-- Step 1.5: 从 ModifyLiquidity 事件聚合出每个 pool 的流动性 (净 delta 累加)
-- 列名按 Dune 上 PoolManager_evt_ModifyLiquidity 实际表结构对齐
-- (列名小写: id / liquidityDelta)
ring_pool_liquidity AS (
    SELECT
        ml.id AS pool,
        -- liquidityDelta 是 int256, 超过 BIGINT (int64) 范围会 overflow,
        -- 改用 DECIMAL(38,0) 保留全量精度后求和.
        SUM(CAST(ml.liquidityDelta AS DECIMAL(38, 0))) AS liquidity_net_delta,
        COUNT(*)                                         AS liquidity_event_count,
        MAX(ml.evt_block_time)                           AS last_liquidity_event_at
    FROM uniswap_v4_ethereum.poolmanager_evt_modifyliquidity ml
    INNER JOIN ring_pools rp
        ON ml.id = rp.pool
    GROUP BY 1
),

-- Step 2: 30 天交易聚合
ring_trades_30d AS (
    SELECT
        t.maker AS pool,
        COUNT(DISTINCT t.tx_hash) AS swap_count_30d,
        SUM(t.amount_usd)          AS total_volume_30d
    FROM dex.trades t
    INNER JOIN ring_pools rp
        ON t.maker = rp.pool
    WHERE t.project = 'uniswap'
      AND t.version = '4'
      AND t.blockchain = 'ethereum'
      AND t.block_time >= NOW() - INTERVAL '30' DAY
    GROUP BY 1
),

-- Step 3: 7 天交易聚合
ring_trades_7d AS (
    SELECT
        t.maker AS pool,
        COUNT(DISTINCT t.tx_hash) AS swap_count_7d,
        SUM(t.amount_usd)          AS total_volume_7d
    FROM dex.trades t
    INNER JOIN ring_pools rp
        ON t.maker = rp.pool
    WHERE t.project = 'uniswap'
      AND t.version = '4'
      AND t.blockchain = 'ethereum'
      AND t.block_time >= NOW() - INTERVAL '7' DAY
    GROUP BY 1
)

-- Step 4: 拼装最终输出
SELECT
    rh.hook_name,
    lower(concat('0x', to_hex(rp.hooks))) AS hook_address,
    lower(concat('0x', to_hex(rp.pool)))  AS pool_id,
    -- === Pool 重要属性 (元信息) ===
    rp.pair,
    rp.fee_in_percent,                                 -- 静态费率 (Ring FewToken 池全为 0)
    COALESCE(rl.liquidity_net_delta, 0) AS liquidity, -- 净 delta 近似 (uint128 累加)
    rl.liquidity_event_count,                          -- 该 pool 累计 modify 事件数
    rp.current_tick,
    rp.tickspacing,
    rp.token0_symbol,
    rp.token1_symbol,
    -- === 30d 交易指标 ===
    COALESCE(t30.swap_count_30d, 0)    AS swap_count_30d,
    COALESCE(t30.total_volume_30d, 0)  AS total_volume_30d,
    ROUND(COALESCE(t30.total_volume_30d, 0) * NULLIF(rp.fee_in_percent, 0) / 10000.0, 4) AS total_fees_30d,
    -- === 7d 交易指标 ===
    COALESCE(t7.swap_count_7d, 0)      AS swap_count_7d,
    COALESCE(t7.total_volume_7d, 0)    AS total_volume_7d,
    ROUND(COALESCE(t7.total_volume_7d, 0)   * NULLIF(rp.fee_in_percent, 0) / 10000.0, 4) AS total_fees_7d,
    -- === 其他元信息 ===
    rp.created_time            AS pool_created_at,
    rl.last_liquidity_event_at
FROM ring_hooks rh
LEFT JOIN ring_pools rp
    ON rp.hooks = rh.hook_address
LEFT JOIN ring_pool_liquidity rl
    ON rl.pool = rp.pool
LEFT JOIN ring_trades_30d t30
    ON t30.pool = rp.pool
LEFT JOIN ring_trades_7d t7
    ON t7.pool = rp.pool
ORDER BY t30.total_volume_30d DESC NULLS LAST