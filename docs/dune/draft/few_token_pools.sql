-- 找 FewUSDC/USDT/DAI/WBTC/CBBTC/UNI 等所有 FewTokenHook 的池子 + token
WITH few_hooks AS (
    SELECT * FROM (VALUES
        ('FewETHHook',    0x044301939deb7ca53c4733dd4d9b3bc5ea0c6888),
        ('FewUSDC',       0x4b2eb653d13e6c9ac5a0a01fde22f2c8d6592888),
        ('FewUSDT',       0xbadf77d50478b4432ef1f243b9c0bc7869486888),
        ('FewDAI',        0x85b648a64aed6307d5d5ce26e6ae086c17bde888),
        ('FewWBTC',       0x0fe942afdb2f51e25cbf892aad175c6a574f2888),
        ('FewCBBTC',      0x8347b7a3807c681513d2b51b8223e59aa16a2888),
        ('FewUNI',        0x4b3e2a8cf36c7eb0fba2a5b39b20c896c6f22888),
        ('FewWEETH',      0x75ae0292e8ad3ab60b9a1a7b3046d3f4abdfa888),
        ('FewWSTETH',     0x877323adbf747f85eb8d182d42f01f34a5492888)
    ) AS t(hook_name, hook_address)
)
SELECT
    fh.hook_name,
    fh.hook_address,
    lower(concat('0x', to_hex(p.pool)))  AS pool_id,
    p.pair,
    p.token0_symbol,
    p.token1_symbol,
    p.token0_address,
    p.token1_address,
    p.fee_in_percent
FROM dune.uniswap_fnd.result_uniswap_v_4_all_pools_data p
INNER JOIN few_hooks fh
    ON p.hooks = fh.hook_address
WHERE p.blockchain = 'ethereum'
ORDER BY fh.hook_name;
