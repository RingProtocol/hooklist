-- 按天时间序列 (看 wrap/unwrap 是否有周期性)
WITH t AS (
    SELECT
        block_time, tx_hash, token_sold_symbol, amount_usd
    FROM dex.trades
    WHERE project = 'uniswap' AND version = '4' AND blockchain = 'ethereum'
      AND maker = 0x7a5a8f5a36a6a2e9961caf6bb047a5a7580d0fe16a532aad93efc596028dfa54
      AND block_time >= NOW() - INTERVAL '30' DAY
)
SELECT
    DATE_TRUNC('day', block_time) AS day,
    COUNT(DISTINCT tx_hash)       AS swap_count,
    ROUND(SUM(amount_usd), 2)     AS daily_usd,
    COUNT(DISTINCT CASE WHEN LOWER(token_sold_symbol)='fwweth' THEN tx_hash END) AS unwrap_count,
    COUNT(DISTINCT CASE WHEN LOWER(token_sold_symbol)='eth'    THEN tx_hash END) AS wrap_count
FROM t
GROUP BY 1
ORDER BY 1 DESC;
