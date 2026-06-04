-- =============================================================
-- Dashboard 04: 每日交易量时间序列 (按 pool × action 切分)
-- 监控 wrap/unwrap 流量的时间趋势, 触发异常告警 (某日 volume > 7d avg * 3)
--
-- 字段:
--   day         - UTC 日期
--   hook_name   - 池子名
--   pair        - token pair
--   action      - WRAP / UNWRAP
--   swap_count  - 当日 swap 数
--   total_usd   - 当日美元量
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
    SELECT rh.hook_name, p.pool, p.pair
    FROM dune.uniswap_fnd.result_uniswap_v_4_all_pools_data p
    INNER JOIN ring_hooks rh ON p.hooks = rh.hook_address
    WHERE p.blockchain = 'ethereum'
)

SELECT
    DATE_TRUNC('day', t.block_time)                                    AS day,
    rp.hook_name,
    rp.pair,
    CASE WHEN STARTS_WITH(LOWER(t.token_sold_symbol), 'fw')
         THEN 'UNWRAP' ELSE 'WRAP' END                                AS action,
    COUNT(DISTINCT t.tx_hash)                                         AS swap_count,
    ROUND(SUM(t.amount_usd), 2)                                       AS total_usd,
    COUNT(DISTINCT t.tx_from)                                         AS unique_callers
FROM dex.trades t
INNER JOIN ring_pools rp ON t.maker = rp.pool
WHERE t.project = 'uniswap'
  AND t.version = '4'
  AND t.blockchain = 'ethereum'
  AND t.block_time >= NOW() - INTERVAL '30' DAY
GROUP BY 1, rp.hook_name, rp.pair, 4
ORDER BY day DESC, total_usd DESC;
