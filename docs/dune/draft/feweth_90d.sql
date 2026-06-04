-- 全时间窗口 (90d) 看是否有 wrap 出现过
WITH t AS (
    SELECT
        block_time, tx_hash, token_sold_symbol, amount_usd
    FROM dex.trades
    WHERE project = 'uniswap' AND version = '4' AND blockchain = 'ethereum'
      AND maker = 0x7a5a8f5a36a6a2e9961caf6bb047a5a7580d0fe16a532aad93efc596028dfa54
      AND block_time >= NOW() - INTERVAL '90' DAY
)
SELECT
    CASE
        WHEN LOWER(token_sold_symbol) = 'fwweth' THEN 'UNWRAP (fwWETH → ETH)'
        WHEN LOWER(token_sold_symbol) = 'eth'    THEN 'WRAP   (ETH → fwWETH)'
        ELSE CONCAT('OTHER: ', COALESCE(token_sold_symbol,'?'))
    END AS action,
    COUNT(*)                            AS trade_count,
    ROUND(SUM(amount_usd), 2)           AS total_usd
FROM t
GROUP BY 1
ORDER BY trade_count DESC;
