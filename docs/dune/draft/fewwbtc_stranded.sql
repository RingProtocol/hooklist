-- FewWBTC 池子的累计 WBTC 净流入 (即池子里"沉淀"的 WBTC 量)
-- 假设: 池子只通过 trade 进出 (忽略 ML 事件造成的储备变化)
WITH rp AS (
    SELECT p.pool
    FROM dune.uniswap_fnd.result_uniswap_v_4_all_pools_data p
    WHERE p.blockchain = 'ethereum'
      AND p.hooks = 0x0fe942afdb2f51e25cbf892aad175c6a574f2888
)
SELECT
    -- 累计 token_sold = 净流入池子的量 (因为只有 WRAP: 用户卖 WBTC, 池子收 WBTC)
    -- 累计 token_bought = 净流出池子的量 (池子付出 fwWBTC)
    ROUND(SUM(CASE WHEN t.token_sold_symbol = 'WBTC'  THEN t.token_sold_amount ELSE 0 END), 4) AS wbtc_inflow,
    ROUND(SUM(CASE WHEN t.token_bought_symbol = 'WBTC' THEN t.token_bought_amount ELSE 0 END), 4) AS wbtc_outflow,
    -- 净沉淀 = 流入 - 流出
    ROUND(
      SUM(CASE WHEN t.token_sold_symbol = 'WBTC'  THEN t.token_sold_amount ELSE 0 END) -
      SUM(CASE WHEN t.token_bought_symbol = 'WBTC' THEN t.token_bought_amount ELSE 0 END)
    , 4) AS wbtc_net_stranded,
    -- 累计 fwWBTC 净流出 (池子付出)
    ROUND(SUM(CASE WHEN t.token_bought_symbol = 'fwWBTC' THEN t.token_bought_amount ELSE 0 END), 4) AS fwwbtc_outflow,
    ROUND(SUM(CASE WHEN t.token_sold_symbol = 'fwWBTC' THEN t.token_sold_amount ELSE 0 END), 4) AS fwwbtc_inflow,
    ROUND(
      SUM(CASE WHEN t.token_sold_symbol = 'fwWBTC' THEN t.token_sold_amount ELSE 0 END) -
      SUM(CASE WHEN t.token_bought_symbol = 'fwWBTC' THEN t.token_bought_amount ELSE 0 END)
    , 4) AS fwwbtc_net_stranded,
    -- USD
    ROUND(SUM(t.amount_usd), 2) AS total_usd,
    COUNT(*) AS trade_count
FROM dex.trades t
INNER JOIN rp ON t.maker = rp.pool
WHERE t.project = 'uniswap' AND t.version = '4' AND t.blockchain = 'ethereum';
