-- =============================================================
-- Dashboard 02: Token 余额 / 沉淀矩阵
-- 监控每个 pool 累计 token 净流入 (被"沉淀"在池子里的量)
--
-- 含义:
--   token0_net_stranded > 0  → pool 沉淀了 token0 (用户从池子拿走了 token1)
--   token0_net_stranded < 0  → pool token0 流出 (用户往池子塞了 token0)
--   反之亦然
--
-- 用途: 当某 token 净沉淀 > 池子当前 reserves 50% 时, 触发 rebalance 预警
-- =============================================================

WITH ring_hooks AS (
    SELECT * FROM (VALUES
        ('FewETHHook',  CAST(0x044301939deb7ca53c4733dd4d9b3bc5ea0c6888 AS varbinary)),
        ('FewUNIHook',  CAST(0x4b3e2a8cf36c7eb0fba2a5b39b20c896c6f22888 AS varbinary)),
        ('FewWBTCHook', CAST(0x0fe942afdb2f51e25cbf892aad175c6a574f2888 AS varbinary)),
        ('FewUSDCHook', CAST(0x4b2eb653d13e6c9ac5a0a01fde22f2c8d6592888 AS varbinary)),
        ('FewDAIHook',  CAST(0x85b648a64aed6307d5d5ce26e6ae086c17bde888 AS varbinary)),
        ('FewUSDTHook', CAST(0xbadf77d50478b4432ef1f243b9c0bc7869486888 AS varbinary)),
        ('FewCBBTCHook',CAST(0x8347b7a3807c681513d2b51b8223e59aa16a2888 AS varbinary)),
        ('FewweETHHook',CAST(0x877323adbf747f85eb8d182d42f01f34a5492888 AS varbinary)),
        ('FewwstETHHook',CAST(0x75ae0292e8ad3ab60b9a1a7b3046d3f4abdfa888 AS varbinary))
    ) AS t(hook_name, hook_address)
),

ring_pools AS (
    SELECT
        rh.hook_name,
        p.pool, p.pair, p.token0_symbol, p.token1_symbol,
        p.token0_address, p.token1_address, p.fee_in_percent
    FROM dune.uniswap_fnd.result_uniswap_v_4_all_pools_data p
    INNER JOIN ring_hooks rh ON p.hooks = rh.hook_address
    WHERE p.blockchain = 'ethereum'
)

SELECT
    rp.hook_name,
    rp.pair,
    rp.token0_symbol,
    rp.token1_symbol,
    ROUND(
      SUM(CASE WHEN t.token_sold_symbol = rp.token0_symbol THEN t.token_sold_amount ELSE 0 END) -
      SUM(CASE WHEN t.token_bought_symbol = rp.token0_symbol THEN t.token_bought_amount ELSE 0 END)
    , 4) AS token0_net_stranded,
    ROUND(
      SUM(CASE WHEN t.token_sold_symbol = rp.token1_symbol THEN t.token_sold_amount ELSE 0 END) -
      SUM(CASE WHEN t.token_bought_symbol = rp.token1_symbol THEN t.token_bought_amount ELSE 0 END)
    , 4) AS token1_net_stranded,
    -- 推断 fwToken 是哪个 (按 symbol 前缀)
    CASE
        WHEN STARTS_WITH(LOWER(rp.token0_symbol), 'fw') THEN rp.token0_symbol
        WHEN STARTS_WITH(LOWER(rp.token1_symbol), 'fw') THEN rp.token1_symbol
        ELSE '?'
    END AS fw_token,
    -- 净沉淀 USD (用 amount_usd 估算, 假设 1 token ≈ 1 USD 等价 stable)
    -- 对 WBTC/ETH 数量 × 价格; 这里简化用 amount_usd / 2
    ROUND(SUM(t.amount_usd), 2) AS all_time_usd,
    COUNT(*) AS trade_count,
    -- 行动方向 (按 token_sold 分类): WRAP-ONLY / UNWRAP-ONLY / MIXED
    CASE
        WHEN SUM(CASE WHEN STARTS_WITH(LOWER(t.token_sold_symbol), 'fw') THEN 1 ELSE 0 END) = COUNT(*) THEN 'UNWRAP-ONLY'
        WHEN SUM(CASE WHEN NOT STARTS_WITH(LOWER(COALESCE(t.token_sold_symbol,'')), 'fw') AND t.token_sold_symbol IS NOT NULL THEN 1 ELSE 0 END) = COUNT(*) THEN 'WRAP-ONLY'
        ELSE 'MIXED'
    END AS action_pattern
FROM dex.trades t
INNER JOIN ring_pools rp ON t.maker = rp.pool
WHERE t.project = 'uniswap'
  AND t.version = '4'
  AND t.blockchain = 'ethereum'
GROUP BY rp.hook_name, rp.pair, rp.token0_symbol, rp.token1_symbol
ORDER BY all_time_usd DESC;
