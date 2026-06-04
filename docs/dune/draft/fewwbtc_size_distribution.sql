-- FewWBTC 池子: 看 WRAP 金额分布 + 池子虚拟流动性
-- 验证 "如果只 WRAP, 池子是否被掏空" 的问题
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
),
trades AS (
    SELECT
        t.block_time,
        t.tx_hash,
        t.token_sold_symbol,
        t.token_bought_symbol,
        t.token_sold_amount,
        t.token_bought_amount,
        t.amount_usd,
        -- token_sold = fwWBTC 是 UNWRAP; 否则是 WRAP (token0_symbol=token0)
        CASE WHEN t.token_sold_address = rp.token1_address THEN 'UNWRAP' ELSE 'WRAP' END AS action
    FROM dex.trades t
    INNER JOIN rp ON t.maker = rp.pool
    WHERE t.project = 'uniswap' AND t.version = '4' AND t.blockchain = 'ethereum'
)
SELECT
    -- 按 ETH 量分桶 (0.001 / 0.01 / 0.1 / 1 / 10+ BTC)
    CASE
        WHEN token_sold_amount < 0.01   THEN '< 0.01 BTC'
        WHEN token_sold_amount < 0.1    THEN '0.01-0.1 BTC'
        WHEN token_sold_amount < 1      THEN '0.1-1 BTC'
        WHEN token_sold_amount < 10     THEN '1-10 BTC'
        ELSE '> 10 BTC'
    END AS size_bucket,
    action,
    COUNT(*)                  AS trade_count,
    ROUND(SUM(token_sold_amount), 4) AS total_btc,
    ROUND(SUM(amount_usd), 2) AS total_usd,
    ROUND(AVG(token_sold_amount), 4) AS avg_btc,
    ROUND(MAX(token_sold_amount), 4) AS max_btc
FROM trades
GROUP BY 1, 2
ORDER BY action, MIN(token_sold_amount);
