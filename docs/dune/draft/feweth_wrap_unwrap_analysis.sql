-- 用 dex.trades 分类 FewETHHook pool 的 wrap/unwrap
-- 规则: token_sold = fwWETH → UNWRAP; token_sold = ETH → WRAP
WITH t AS (
    SELECT
        block_time,
        tx_hash,
        taker,
        tx_from,
        maker,
        token_sold_symbol,
        token_bought_symbol,
        token_sold_address,
        token_bought_address,
        amount_usd,
        token_sold_amount,
        token_bought_amount
    FROM dex.trades
    WHERE project = 'uniswap'
      AND version = '4'
      AND blockchain = 'ethereum'
      AND maker = 0x7a5a8f5a36a6a2e9961caf6bb047a5a7580d0fe16a532aad93efc596028dfa54
)
SELECT
    CASE
        WHEN LOWER(token_sold_symbol) = 'fwweth' THEN 'UNWRAP (fwWETH → ETH)'
        WHEN LOWER(token_sold_symbol) = 'eth'    THEN 'WRAP   (ETH → fwWETH)'
        ELSE CONCAT('OTHER: ', COALESCE(token_sold_symbol,'?'), ' → ', COALESCE(token_bought_symbol,'?'))
    END AS action,
    COUNT(*)                                  AS trade_count,
    COUNT(DISTINCT tx_hash)                   AS swap_count,
    ROUND(SUM(amount_usd), 2)                 AS total_usd,
    ROUND(SUM(token_sold_amount), 4)          AS total_sold,
    ROUND(SUM(token_bought_amount), 4)        AS total_bought,
    COUNT(DISTINCT tx_from)                   AS unique_eoas,
    COUNT(DISTINCT taker)                     AS unique_takers,
    MIN(block_time)                           AS first_trade,
    MAX(block_time)                           AS last_trade
FROM t
WHERE block_time >= NOW() - INTERVAL '30' DAY
GROUP BY 1
ORDER BY trade_count DESC;
