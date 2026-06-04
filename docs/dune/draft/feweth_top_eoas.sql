-- Top EOAs / Takers (谁在触发 unwrap)
WITH t AS (
    SELECT
        block_time, tx_hash, taker, tx_from, maker,
        token_sold_amount, token_bought_amount, amount_usd
    FROM dex.trades
    WHERE project = 'uniswap' AND version = '4' AND blockchain = 'ethereum'
      AND maker = 0x7a5a8f5a36a6a2e9961caf6bb047a5a7580d0fe16a532aad93efc596028dfa54
      AND LOWER(token_sold_symbol) = 'fwweth'
      AND block_time >= NOW() - INTERVAL '30' DAY
)
SELECT
    tx_from                       AS eoa,
    COUNT(DISTINCT tx_hash)       AS swap_count,
    ROUND(SUM(token_sold_amount), 4) AS total_fwweth,
    ROUND(SUM(amount_usd), 2)     AS total_usd,
    COUNT(DISTINCT DATE_TRUNC('day', block_time)) AS active_days
FROM t
GROUP BY 1
ORDER BY swap_count DESC
LIMIT 20;
