-- 按 ETH 量分桶 (散户 vs 大户)
WITH t AS (
    SELECT
        block_time, tx_hash, taker, tx_from, token_sold_amount, amount_usd
    FROM dex.trades
    WHERE project = 'uniswap' AND version = '4' AND blockchain = 'ethereum'
      AND maker = 0x7a5a8f5a36a6a2e9961caf6bb047a5a7580d0fe16a532aad93efc596028dfa54
      AND LOWER(token_sold_symbol) = 'fwweth'
      AND block_time >= NOW() - INTERVAL '30' DAY
)
SELECT
    CASE
        WHEN token_sold_amount < 0.01  THEN '< 0.01 ETH'
        WHEN token_sold_amount < 0.1   THEN '0.01-0.1 ETH'
        WHEN token_sold_amount < 1     THEN '0.1-1 ETH'
        WHEN token_sold_amount < 10    THEN '1-10 ETH'
        WHEN token_sold_amount < 100   THEN '10-100 ETH'
        ELSE '> 100 ETH'
    END AS size_bucket,
    COUNT(*)                                  AS trade_count,
    COUNT(DISTINCT tx_hash)                   AS swap_count,
    ROUND(SUM(token_sold_amount), 4)          AS total_eth,
    ROUND(SUM(amount_usd), 2)                 AS total_usd,
    ROUND(AVG(token_sold_amount), 4)          AS avg_eth,
    ROUND(AVG(amount_usd), 2)                 AS avg_usd
FROM t
GROUP BY 1
ORDER BY MIN(token_sold_amount);
