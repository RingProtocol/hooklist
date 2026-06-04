-- Top Takers (调用 PoolManager.swap 的合约, 通常是 router/aggregator/hook)
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
    taker                            AS contract,
    COUNT(DISTINCT tx_hash)          AS swap_count,
    ROUND(SUM(token_sold_amount), 4) AS total_fwweth,
    ROUND(SUM(amount_usd), 2)        AS total_usd,
    COUNT(DISTINCT tx_from)          AS unique_callers,
    MIN(block_time)                  AS first_call,
    MAX(block_time)                  AS last_call
FROM t
GROUP BY 1
ORDER BY swap_count DESC
LIMIT 20;
