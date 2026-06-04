-- 9 个池子的 "stranded value" 矩阵:
--   WRAP-only 池子 → 沉淀 underlying, 抽干 fwToken
--   UNWRAP-only 池子 → 沉淀 fwToken, 抽干 underlying
WITH ring_hooks AS (
    SELECT * FROM (VALUES
        ('FewETHHook',  CAST(0x044301939deb7ca53c4733dd4d9b3bc5ea0c6888 AS varbinary)),
        ('FewUSDC',     CAST(0x4b2eb653d13e6c9ac5a0a01fde22f2c8d6592888 AS varbinary)),
        ('FewUSDT',     CAST(0xbadf77d50478b4432ef1f243b9c0bc7869486888 AS varbinary)),
        ('FewDAI',      CAST(0x85b648a64aed6307d5d5ce26e6ae086c17bde888 AS varbinary)),
        ('FewWBTC',     CAST(0x0fe942afdb2f51e25cbf892aad175c6a574f2888 AS varbinary)),
        ('FewCBBTC',    CAST(0x8347b7a3807c681513d2b51b8223e59aa16a2888 AS varbinary)),
        ('FewUNI',      CAST(0x4b3e2a8cf36c7eb0fba2a5b39b20c896c6f22888 AS varbinary)),
        ('FewWEETH',    CAST(0x75ae0292e8ad3ab60b9a1a7b3046d3f4abdfa888 AS varbinary)),
        ('FewWSTETH',   CAST(0x877323adbf747f85eb8d182d42f01f34a5492888 AS varbinary))
    ) AS t(hook_name, hook_address)
),
ring_pools AS (
    SELECT rh.hook_name, p.pool, p.pair, p.token0_symbol, p.token1_symbol,
           p.token0_address, p.token1_address
    FROM dune.uniswap_fnd.result_uniswap_v_4_all_pools_data p
    INNER JOIN ring_hooks rh ON p.hooks = rh.hook_address
    WHERE p.blockchain = 'ethereum'
)
SELECT
    rp.hook_name,
    rp.pair,
    rp.token0_symbol,
    rp.token1_symbol,
    -- 用 symbol 识别哪个是 underlying (没 fw 前缀) 哪个是 fwToken
    -- token0_sold / token0_bought: token0 进出
    -- token1_sold / token1_bought: token1 进出
    ROUND(SUM(CASE WHEN t.token_sold_symbol = rp.token0_symbol  THEN t.token_sold_amount ELSE 0 END), 4)  AS tok0_sold,
    ROUND(SUM(CASE WHEN t.token_bought_symbol = rp.token0_symbol THEN t.token_bought_amount ELSE 0 END), 4) AS tok0_bought,
    ROUND(SUM(CASE WHEN t.token_sold_symbol = rp.token1_symbol  THEN t.token_sold_amount ELSE 0 END), 4)  AS tok1_sold,
    ROUND(SUM(CASE WHEN t.token_bought_symbol = rp.token1_symbol THEN t.token_bought_amount ELSE 0 END), 4) AS tok1_bought,
    -- 净变化 (positive = 池子净流入, negative = 池子净流出)
    ROUND(
      SUM(CASE WHEN t.token_sold_symbol = rp.token0_symbol THEN t.token_sold_amount ELSE 0 END) -
      SUM(CASE WHEN t.token_bought_symbol = rp.token0_symbol THEN t.token_bought_amount ELSE 0 END)
    , 4) AS tok0_net_stranded,
    ROUND(
      SUM(CASE WHEN t.token_sold_symbol = rp.token1_symbol THEN t.token_sold_amount ELSE 0 END) -
      SUM(CASE WHEN t.token_bought_symbol = rp.token1_symbol THEN t.token_bought_amount ELSE 0 END)
    , 4) AS tok1_net_stranded,
    ROUND(SUM(t.amount_usd), 2) AS total_usd,
    COUNT(*) AS trade_count
FROM dex.trades t
INNER JOIN ring_pools rp ON t.maker = rp.pool
WHERE t.project = 'uniswap' AND t.version = '4' AND t.blockchain = 'ethereum'
GROUP BY rp.hook_name, rp.pair, rp.token0_symbol, rp.token1_symbol
ORDER BY total_usd DESC;
