-- 9 个 FewToken Hook 池子的全时间 wrap/unwrap + 流动性聚合
-- 直接 JOIN dune.uniswap_fnd.result_uniswap_v_4_all_pools_data 拿 pool_id,
-- 避免 varbinary 字面量编码不匹配的问题.
WITH ring_hooks AS (
    SELECT * FROM (VALUES
        ('FewETHHook',  CAST(0x044301939deb7ca53c4733dd4d9b3bc5ea0c6888 AS varbinary)),
        ('FewUSDC',     CAST(0x4b2eb653d13e6c9ac5a0a01fde22f2c8d6592888 AS varbinary)),
        ('FewUSDT',     CAST(0xbadf77d50478b4432ef1f243b9c0bc7869486888 AS varbinary)),
        ('FewDAI',      CAST(0x85b648a64aed6307d5d5ce26e6ae086c17bde888 AS varbinary)),
        ('FewWBTC',     CAST(0x0fe942afdb2f51e25cbf892aad175c6a574f2888 AS varbinary)),
        ('FewCBBTC',    CAST(0x8347b7a3807c681513d2b51b8223e59aa16a2888 AS varbinary)),
        ('FewUNI',      CAST(0x4b3e2a8cf36c7eb0fba2a5b39b20c896c6f22888 AS varbinary)),
        ('FewWEETH',    CAST(0x75ae0292e8ad3ab60b9a1a7b3046d3f4abdfa888 AS varbinary)),
        ('FewWSTETH',   CAST(0x877323adbf747f85eb8d182d42f01f34a5492888 AS varbinary))
    ) AS t(hook_name, hook_address)
),
ring_pools AS (
    SELECT
        rh.hook_name,
        p.pool, p.hooks, p.pair, p.token0_symbol, p.token1_symbol,
        p.token0_address, p.token1_address, p.fee_in_percent
    FROM dune.uniswap_fnd.result_uniswap_v_4_all_pools_data p
    INNER JOIN ring_hooks rh ON p.hooks = rh.hook_address
    WHERE p.blockchain = 'ethereum'
),
trade_stats AS (
    SELECT
        rp.hook_name,
        rp.pair,
        rp.token0_symbol,
        rp.token1_symbol,
        COUNT(*)                                            AS total_trades,
        COUNT(DISTINCT t.tx_hash)                            AS total_swaps,
        ROUND(SUM(t.amount_usd), 2)                         AS all_time_usd,
        SUM(CASE WHEN STARTS_WITH(LOWER(t.token_sold_symbol), 'fw') THEN 1 ELSE 0 END) AS unwrap_count,
        SUM(CASE WHEN NOT STARTS_WITH(LOWER(COALESCE(t.token_sold_symbol,'')), 'fw')
                  AND t.token_sold_symbol IS NOT NULL THEN 1 ELSE 0 END) AS wrap_count,
        MIN(t.block_time)                                   AS first_trade,
        MAX(t.block_time)                                   AS last_trade
    FROM dex.trades t
    INNER JOIN ring_pools rp ON t.maker = rp.pool
    WHERE t.project = 'uniswap'
      AND t.version = '4'
      AND t.blockchain = 'ethereum'
    GROUP BY rp.hook_name, rp.pair, rp.token0_symbol, rp.token1_symbol
),
liquidity_stats AS (
    SELECT
        rp.hook_name,
        SUM(CAST(ml.liquidityDelta AS DECIMAL(38, 0))) AS liquidity_net_delta,
        COUNT(*)                                          AS ml_events,
        MIN(ml.evt_block_time)                            AS first_ml,
        MAX(ml.evt_block_time)                            AS last_ml
    FROM uniswap_v4_ethereum.poolmanager_evt_modifyliquidity ml
    INNER JOIN ring_pools rp ON ml.id = rp.pool
    GROUP BY rp.hook_name
)
SELECT
    rp.hook_name,
    rp.pair,
    COALESCE(ts.total_trades, 0)        AS total_trades,
    COALESCE(ts.unwrap_count, 0)       AS unwrap_count,
    COALESCE(ts.wrap_count, 0)         AS wrap_count,
    COALESCE(ts.all_time_usd, 0)       AS all_time_usd,
    ts.first_trade,
    ts.last_trade,
    ls.liquidity_net_delta,
    ls.ml_events,
    ls.first_ml                        AS first_ml_at,
    ls.last_ml                         AS last_ml_at
FROM ring_pools rp
LEFT JOIN trade_stats ts      ON ts.hook_name = rp.hook_name
LEFT JOIN liquidity_stats ls  ON ls.hook_name = rp.hook_name
ORDER BY COALESCE(ts.all_time_usd, 0) DESC;
