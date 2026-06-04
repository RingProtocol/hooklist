-- =============================================================
-- Dashboard 03: Top 交易者 (按 pool 切分)
-- 监控每个 hook pool 的 top EOA 调用者, 看谁是核心用户 / 机器人 / 套利者
--
-- 字段:
--   hook_name    - 池子名
--   caller_rank  - 在该 pool 内的排名
--   tx_from      - EOA 调用者地址
--   swap_count   - 累计 trade 数
--   total_usd    - 累计美元量
--   first_tx     - 首次交易时间
--   last_tx      - 最后交易时间
--   active_days  - 活跃天数 (高 = 真实用户, 低 = 一次性机器人)
--   pattern      - 行为模式: WRAP / UNWRAP / MIXED
-- =============================================================

WITH ring_hooks AS (
    SELECT * FROM (VALUES
        ('FewETHHook',  CAST(0x044301939deb7ca53c4733dd4d9b3bc5ea0c6888 AS varbinary)),
        ('FewUNIHook',  CAST(0x4b3e2a8cf36c7eb0fba2a5b39b20c896c6f22888 AS varbinary)),
        ('FewWBTCHook', CAST(0x0fe942afdb2f51e25cbf892aad175c6a574f2888 AS varbinary)),
        ('FewUSDCHook', CAST(0x4b2eb653d13e6c9ac5a0a01fde22f2c8d6592888 AS varbinary)),
        ('FewDAIHook',  CAST(0x85b648a64aed6307d5d5ce26e6ae086c17bde888 AS varbinary)),
        ('FewUSDTHook', CAST(0xbadf77d50478b4432ef1f243b9c0bc7869486888 AS varbinary)),
        ('FewCBBTCHook',CAST(0x8347b7a3807c681513d2b51b8223e59aa16a2888 AS varbinary)),
        ('FewweETHHook',CAST(0x877323adbf747f85eb8d182d42f01f34a5492888 AS varbinary)),
        ('FewwstETHHook',CAST(0x75ae0292e8ad3ab60b9a1a7b3046d3f4abdfa888 AS varbinary))
    ) AS t(hook_name, hook_address)
),

ring_pools AS (
    SELECT
        rh.hook_name, p.pool, p.pair, p.token0_symbol, p.token1_symbol
    FROM dune.uniswap_fnd.result_uniswap_v_4_all_pools_data p
    INNER JOIN ring_hooks rh ON p.hooks = rh.hook_address
    WHERE p.blockchain = 'ethereum'
),

caller_stats AS (
    SELECT
        rp.hook_name,
        rp.pair,
        t.tx_from                                                         AS caller,
        COUNT(DISTINCT t.tx_hash)                                         AS swap_count,
        ROUND(SUM(t.amount_usd), 2)                                       AS total_usd,
        MIN(t.block_time)                                                 AS first_tx,
        MAX(t.block_time)                                                 AS last_tx,
        COUNT(DISTINCT DATE_TRUNC('day', t.block_time))                   AS active_days,
        -- 行为模式
        CASE
            WHEN SUM(CASE WHEN STARTS_WITH(LOWER(t.token_sold_symbol), 'fw') THEN 1 ELSE 0 END) = COUNT(*) THEN 'UNWRAP'
            WHEN SUM(CASE WHEN NOT STARTS_WITH(LOWER(COALESCE(t.token_sold_symbol,'')), 'fw') AND t.token_sold_symbol IS NOT NULL THEN 1 ELSE 0 END) = COUNT(*) THEN 'WRAP'
            ELSE 'MIXED'
        END AS pattern
    FROM dex.trades t
    INNER JOIN ring_pools rp ON t.maker = rp.pool
    WHERE t.project = 'uniswap'
      AND t.version = '4'
      AND t.blockchain = 'ethereum'
    GROUP BY rp.hook_name, rp.pair, t.tx_from
)

SELECT
    hook_name,
    pair,
    caller,
    swap_count,
    total_usd,
    first_tx,
    last_tx,
    active_days,
    pattern,
    -- 同一 caller 跨多池子的标记 (留作扩展, 这里用单池内的排名替代)
    ROW_NUMBER() OVER (PARTITION BY hook_name ORDER BY total_usd DESC) AS caller_rank
FROM caller_stats
ORDER BY hook_name, total_usd DESC;
