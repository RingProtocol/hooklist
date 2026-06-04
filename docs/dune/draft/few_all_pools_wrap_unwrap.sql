-- 9 个 FewToken Hook pool 的 30d wrap/unwrap 对比
-- 分类规则: 池子里的 fwToken (wrapper) vs underlying
--   - token_sold = fwToken  → UNWRAP (fwToken → underlying)
--   - token_sold = underlying → WRAP (underlying → fwToken)
WITH pools AS (
    SELECT * FROM (VALUES
        ('FewETHHook', 0x7a5a8f5a36a6a2e9961caf6bb047a5a7580d0fe16a532aad93efc596028dfa54, 0x0000000000000000000000000000000000000000, 0xa250cc729bb3323e7933022a67b52200fe354767, 'ETH/fwWETH'),
        ('FewUSDC',    0x5837e6b4fd4b8193f2f7a8b4490c0f154344bb9a52b36a885578ff6d31eff20a, 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48, 0x0492560fa7cfd6a85e50d8be3f77318994f8f429, 'USDC/fwUSDC'),
        ('FewUSDT',    0x7db868544c8f7f6ddb107c7749c94f03c9e0155f2138aef3f8a020e4a4e9f2f5, 0xdac17f958d2ee523a2206206994597c13d831ec7, 0xef87f4608e601e8564800265aee1c1ffadf73283, 'USDT/fwUSDT'),
        ('FewDAI',     0xf906beb74154ca4d057b7079c90eb1044efaf40ef468e62ec983930cf8c46cb9, 0x6b175474e89094c44da98b954eedeac495271d0f, 0x8a6fe57c08c84e0f4ee97aae68a62e820a37d259, 'DAI/fwDAI'),
        ('FewWBTC',    0x18605c7a76101aeccc414cc300dd5e5ae44b30d6c247ba164ccd88952c7e0f9d, 0x2260fac5e5542a773aa44fbcfedf7c193bc2c599, 0x2078f336fdd260f708bec4a20c82b063274e1b23, 'WBTC/fwWBTC'),
        ('FewCBBTC',   0x8f8b0b21fb429ffb5210f2bf0f8b7cb267b944a0c61beaae35f20f6839c4f8f9, 0xcbb7c0000ab88b473b1f5afd9ef808440eed33bf, 0xdbf1703e5d29afefbf1bd958ce7a6023c67f3e5d, 'cbBTC/fwcbBTC'),
        ('FewUNI',     0x301d41ff23b73b209ab2b1112f4effd0d8ff978ec29d743c1431463f84f6c0a3, 0x1f9840a85d5af5bf1d1762f925bdaddc4201f984, 0xe8e1f50392bd61d0f8f48e8e7af51d3b8a52090a, 'UNI/fwUNI'),
        ('FewWEETH',   0xe7c2f30fd89238331b0e3e6ac6351578d5e3091b7839eff321c29cf88e76a3a6, 0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0, 0xb90e63487bc6a4fa3d58f707510dab3c28a63137, 'wstETH/fwwstETH'),
        ('FewWSTETH',  0x6933dfbf7441cc4ee4439843fdd464e215a6c90f07c5a769198e2a047f9c4d2b, 0xcd5fe23c85820f7b72d0926fc9b05b43e359b7ee, 0x9553d5f1f564ede30f5a9f0274cd0af7a00546e7, 'weETH/fwweETH')
    ) AS t(hook_name, pool_id, underlying_addr, fw_addr, pair)
),
t AS (
    SELECT
        p.hook_name,
        p.pair,
        t.block_time,
        t.tx_hash,
        t.token_sold_address,
        t.token_bought_address,
        t.token_sold_symbol,
        t.token_bought_symbol,
        t.amount_usd,
        t.token_sold_amount,
        t.token_bought_amount
    FROM dex.trades t
    INNER JOIN pools p
        ON t.maker = p.pool_id
    WHERE t.project = 'uniswap'
      AND t.version = '4'
      AND t.blockchain = 'ethereum'
      AND t.block_time >= NOW() - INTERVAL '30' DAY
)
SELECT
    p.hook_name,
    p.pair,
    CASE
        WHEN t.token_sold_address = p.fw_addr        THEN 'UNWRAP'
        WHEN t.token_sold_address = p.underlying_addr THEN 'WRAP'
        ELSE 'UNKNOWN'
    END AS action,
    COUNT(DISTINCT t.tx_hash)         AS swap_count,
    ROUND(SUM(t.amount_usd), 2)       AS total_usd,
    ROUND(SUM(t.token_sold_amount), 4) AS total_sold
FROM dex.trades t
INNER JOIN pools p
    ON t.maker = p.pool_id
WHERE t.project = 'uniswap'
  AND t.version = '4'
  AND t.blockchain = 'ethereum'
  AND t.block_time >= NOW() - INTERVAL '30' DAY
GROUP BY 1, 2, 3
ORDER BY p.hook_name, action;
