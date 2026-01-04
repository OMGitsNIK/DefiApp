# Project Summary

Project: Minimal decentralized USD-pegged stablecoin (Foundry project)

Key concepts:
- Collateral-backed minting and burning
- Chainlink price feeds for ETH/BTC to USD conversion

Important files:
- `src/DecentralizedStableCoin.sol` — token contract
- `src/DSCEngine.sol` — collateral and mint/burn engine
- `test/unit/DSCEngineTest.t.sol` — unit tests
- `test/mocks/` — mocks (`MockV3Aggregator.sol`, `ERC20Mock.sol`)
- `foundry.toml` — Foundry config

How to run tests:
```bash
cd "DeFi-Stablecoin/DefiApp"
forge test
```

Test snapshot (run on 2026-01-04):
- 2 tests passed; 0 failed; 0 skipped

Notes:
- Collateral types: wETH, wBTC (as noted in README)
- Dependencies: `lib/forge-std`, `lib/openzeppelin-contracts`, Chainlink contracts
