-- FewETHHook 的 3 次 ModifyLiquidity 事件 + 当前 TVL
SELECT
    evt_block_time,
    evt_block_number,
    evt_tx_hash,
    liquidityDelta,
    tickLower,
    tickUpper,
    salt,
    evt_tx_from,
    evt_tx_to
FROM uniswap_v4_ethereum.poolmanager_evt_modifyliquidity
WHERE id = 0x7a5a8f5a36a6a2e9961caf6bb047a5a7580d0fe16a532aad93efc596028dfa54
ORDER BY evt_block_time;
