-- FewWBTC 池子: WRAP-only 验证 + 金额分布
-- 分类: token_sold_symbol starts with 'fw' → UNWRAP, 否则 WRAP
WITH rp AS (
    SELECT
        rh.hook_name,
        p.pool, p.pair, p.token0_symbol, p.token1_symbol,
        p.token0_address, p.token1_address
    FROM dune.uniswap_fnd.result_uniswap_v_4_all_pools_data p
    INNER JOIN (VALUES
        ('FewWBTC', CAST(0x0fe942afdb2f51e25cbf892aad175c6a574f2888 AS varbinary))
    ) AS rh(hook_name, hook_address) ON p.hooks = rh.hook_address
    WHERE p.blockchain = 'ethereum'
)
SELECT
    t.block_time,
    t.tx_hash,
    t.token_sold_symbol,
    t.token_bought_symbol,
    t.token_sold_amount,
    t.token_bought_amount,
    t.amount_usd,
    -- 按 token_sold 的 symbol 分类
    CASE WHEN STARTS_WITH(LOWER(t.token_sold_symbol), 'fw') THEN 'UNWRAP' ELSE 'WRAP' END AS action,
    -- 大小桶 (用 token_sold_amount 的实际值, 假设是 BTC)
    CASE
        WHEN t.token_sold_amount < 0.01   THEN '< 0.01 BTC'
        WHEN t.token_sold_amount < 0.1    THEN '0.01-0.1 BTC'
        WHEN t.token_sold_amount < 1      THEN '0.1-1 BTC'
        WHEN t.token_sold_amount < 10     THEN '1-10 BTC'
        ELSE '> 10 BTC'
    END AS size_bucket
FROM dex.trades t
INNER JOIN rp ON t.maker = rp.pool
WHERE t.project = 'uniswap' AND t.version = '4' AND t.blockchain = 'ethereum'
ORDER BY t.token_sold_amount DESC
LIMIT 10;
