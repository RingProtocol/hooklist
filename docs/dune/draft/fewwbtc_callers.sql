-- FewWBTC 257 BTC 的 WRAP 是不是同一个 EOA? (验证 dApp 专用 wrap 假设)
SELECT
    t.tx_from                                                       AS caller,
    COUNT(DISTINCT t.tx_hash)                                       AS tx_count,
    ROUND(SUM(t.token_sold_amount), 4)                              AS total_btc,
    ROUND(SUM(t.amount_usd), 2)                                     AS total_usd,
    MIN(t.block_time)                                               AS first_tx,
    MAX(t.block_time)                                               AS last_tx
FROM dex.trades t
INNER JOIN (
    SELECT p.pool FROM dune.uniswap_fnd.result_uniswap_v_4_all_pools_data p
    WHERE p.blockchain = 'ethereum' AND p.hooks = 0x0fe942afdb2f51e25cbf892aad175c6a574f2888
) rp ON t.maker = rp.pool
WHERE t.project = 'uniswap' AND t.version = '4' AND t.blockchain = 'ethereum'
GROUP BY 1
ORDER BY total_btc DESC
LIMIT 10;
