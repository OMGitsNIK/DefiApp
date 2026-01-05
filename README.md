# DeFi Stablecoin Engine

A minimal, collateral-backed stablecoin system built with Foundry and Solidity.

## Overview

**Relative Stability:** Anchored to the US Dollar

**Stability Mechanism:** Algorithmic, Decentralized Minting/Burning

**Collateral Requirements:** Users may only mint the stablecoin with sufficient exogenous crypto collateral.

**Supported Collateral:**
- wETH (Wrapped Ethereum)
- wBTC (Wrapped Bitcoin)

**Price Feeds:** Chainlink Oracle feeds for ETH/BTC to USD conversion

## Key Features

- Collateral deposit and withdrawal
- Mint/burn DSC (DecentralizedStableCoin) based on collateral ratio
- Real-time USD valuation via Chainlink price feeds
- Revert checks for invalid collateral and unsupported tokens
- Full unit test coverage (6 tests passing)

## Project Structure

```
src/
├── DecentralizedStableCoin.sol    # ERC20 token contract
└── DSCEngine.sol                  # Core minting/burning logic

test/
├── unit/
│   └── DSCEngineTest.t.sol        # Unit tests
└── mocks/
    ├── ERC20Mock.sol
    └── MockV3Aggregator.sol
```


## Deployment

```bash
forge script script/DeployDSC.s.sol
```

## Running Tests

```bash
cd DeFi-Stablecoin/DefiApp
forge test
```

**Test Results (2026-01-05):**
- ✅ ~18 tests passing; 0 failed
  - Comprehensive coverage for:
    - Deposit Integration
    - Price Feed Logic
    - Revert Conditions
    - Constructor Initialization

## Dependencies

- Foundry (forge, cast, anvil)
- OpenZeppelin Contracts
- Chainlink Brownie Contracts

## Development

Built with Solidity 0.8.x and tested with Foundry test framework.