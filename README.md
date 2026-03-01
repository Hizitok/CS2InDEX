# CS2InDEX

**Decentralized Perpetual Trading Platform for CS2 Item Indices**

A fully on-chain perpetual futures exchange for Counter-Strike 2 (CS2) item indices, enabling traders to speculate on CS2 item prices with leverage while providing hedging opportunities for CS2 item holders.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Solidity](https://img.shields.io/badge/Solidity-0.8.20-orange.svg)
![Foundry](https://img.shields.io/badge/Built%20with-Foundry-red.svg)

## Overview

CS2InDEX is inspired by traditional cryptocurrency exchanges like Binance and OKX, but designed specifically for CS2 item index trading. The platform tracks real-world CS2 item indices from sources like [SkinFlow.gg](https://skinflow.gg/csgo-stash/graph/overview) and [EsportFire.com](https://esportfire.com/indexes), including:

- **CS2 Global Index** (~$5B market cap)
- **CS2 Knives Index** (~$709M market cap)
- **CS2 Rifles Index**
- **CS2 Gloves Index**

## Key Features

### 📊 Trading Features
- **Perpetual Futures** - No expiration, continuous trading
- **Leverage Trading** - Up to 10x leverage on positions
- **Long & Short** - Profit from both rising and falling prices
- **NFT Positions** - Each position is an ERC721 NFT (transferable)
- **On-Chain Order Book** - Order Statistics Tree for efficient matching

### 🔒 Risk Management
- **Isolated Margin** - Each position has independent risk
- **Automated Liquidations** - 20% maintenance margin, two-step model
- **Funding Rate** - 8-hour settlement period, ±2% cap
- **Real-Time Oracle** - Continuous price feeds from external sources

### 💰 Fee Structure
- **Maker Fee**: 0.3% (liquidity providers)
- **Taker Fee**: 0.5% (liquidity takers)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    CS2InDEX Platform                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌───────────────┐  ┌───────────────┐  ┌─────────────┐  │
│  │   Vault.sol   │  │   Pool.sol    │  │ Factory.sol │  │
│  │               │  │               │  │             │  │
│  │ Collateral    │  │ Order Book    │  │ Deploy &    │  │
│  │ Management    │  │ Matching      │  │ Manage      │  │
│  └───────────────┘  └───────────────┘  └─────────────┘  │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │              PositionNFT.sol (ERC721)             │  │
│  │          Each position is a transferable NFT      │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────┐  ┌──────────────────┐             │
│  │ Liquidation      │  │  ADL  Engine     │             │
│  │ Engine           │  │  (Planned)       │             │
│  │ Auto liquidate   │  │ Emergency        │             │
│  │ underwater pos.  │  │ deleveraging     │             │
│  └──────────────────┘  └──────────────────┘             │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │           IndexOracle.sol                         │  │
│  │     Price feed + Funding rate settlement          │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
                           ↕
┌─────────────────────────────────────────────────────────┐
│                  Oracle Service (Node.js)               │
│                                                         │
│  Fetches prices from:                                   │
│  • SkinFlow.gg (CS2 Global & Knives Indices)            │
│  • EsportFire.com (Rifles & Gloves Indices)             │
│  • Buff163 (Fallback)                                   │
│                                                         │
│  Updates on-chain oracles every 5 minutes               │
└─────────────────────────────────────────────────────────┘
                           ↕
┌─────────────────────────────────────────────────────────┐
│              Frontend (Next.js + RainbowKit)            │
│                                                         │
│  • Wallet connection (MetaMask, WalletConnect, etc.)    │
│  • Trading interface (Long/Short, Leverage)             │
│  • Position management (Open, Close, Transfer)          │
│  • Vault management (Deposit, Withdraw)                 │
│  • Real-time market data                                │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│              Market Maker                               │
│                                                         │
│  • Trading interface                                    │
│  • Position management                                  │
│  • Algorithm                                            │
│  • Real-time market data                                │
└─────────────────────────────────────────────────────────┘
```

## Project Structure

```
CS2InDEX/
├── src/                      # Smart contracts (Solidity)
│   ├── Factory.sol          # Pool deployment & management
│   ├── Vault.sol            # Collateral vault
│   ├── Pool.sol             # Order book & matching engine
│   ├── PositionNFT.sol      # ERC721 position tokens
│   ├── Liquidation.sol      # Liquidation engine
│   ├── IndexOracle.sol      # Price oracle & funding rate
│   ├── Router.sol           # User interaction entry point
│   └── libraries/           # OS Tree, OrderTypes, PosERC721, etc.
│
├── test/                     # Foundry tests
│   ├── Pool.t.sol           # Pool unit tests
│   ├── Integration.t.sol    # End-to-end integration tests
│   ├── GasBenchmark.t.sol   # Gas benchmarking
│   ├── OrderStatisticsTree.t.sol  # OS Tree tests
│   └── mocks/               # Mock contracts for testing
│
├── deploy/                   # Deployment scripts & artifacts
│   ├── Deploy.s.sol         # Forge deployment script
│   ├── deploy.sh            # One-click deploy + address sync
│   ├── deployed.{chainId}.json  # Deployed addresses (auto-generated)
│   └── README.md            # Deployment guide
│
├── scripts/                  # Developer utility scripts
│   ├── sync-addresses.sh    # Sync deployed addresses → frontend + marketmaker
│   └── start-dev.sh         # Start frontend + market maker together
│
├── frontend/                 # Next.js web application
│   ├── src/
│   │   ├── app/             # Next.js App Router pages
│   │   ├── components/      # React UI components
│   │   └── config/          # Contract ABIs & addresses
│   └── package.json
│
├── oracle-service/           # Price feed backend service
│   ├── src/
│   │   ├── index.ts         # Main service entry
│   │   ├── oracle-updater.ts     # On-chain price updates
│   │   └── price-aggregator.ts   # Fetch from SkinFlow / EsportFire
│   ├── Dockerfile
│   └── docker-compose.yml
│
├── marketmaker/              # Grid market maker bot
│   ├── src/
│   │   ├── bot.ts           # Grid + Martingale strategy
│   │   ├── config.ts        # Bot configuration
│   │   └── contracts.ts     # Contract ABIs
│   └── package.json
│
├── concepts/                 # Background docs & investor materials
│   ├── README.md            # Project concept overview
│   ├── whitepaper.md
│   ├── pitchDeck.md
│   ├── tokenomics.md
│   └── roadshow.md
│
├── foundry.toml             # Foundry configuration
├── .env.example             # Environment template
└── README.md                # This file
```

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) - For smart contracts
- [Node.js v18+](https://nodejs.org/) - For frontend and oracle service
- [Git](https://git-scm.com/) - Version control

### 1. Clone Repository

```bash
git clone https://github.com/yourusername/CS2InDEX.git
cd CS2InDEX
```

### 2. Install Dependencies

```bash
# Install Foundry dependencies
forge install

# Install frontend dependencies
cd frontend
npm install
cd ..

# Install oracle service dependencies
cd oracle-service
npm install
cd ..
```

### 3. Run Tests

```bash
# Run all smart contract tests
forge test

# Run with gas report
forge test --gas-report

# Run specific test file
forge test --match-path test/Pool.t.sol

# Run with verbosity
forge test -vvv
```

### 4. Deploy Contracts (Testnet)

```bash
# Configure environment
cp .env.example .env
# Edit .env: set PRIVATE_KEY and SEPOLIA_RPC_URL

# Deploy to Unichain Sepolia (chainId 1301)
# Automatically syncs addresses to frontend and marketmaker after deploy
bash deploy/deploy.sh sepolia
```

See [deploy/README.md](deploy/README.md) for detailed deployment instructions.

### 5. Start Oracle Service

```bash
cd oracle-service
cp .env.example .env
# Edit .env with deployed oracle address and API keys
npm start
```

### 6. Start Frontend + Market Maker

```bash
# Edit marketmaker/.env: set PRIVATE_KEY (auto-created by deploy.sh)

# Start both together (market maker in background, frontend in foreground)
bash scripts/start-dev.sh

# Or separately:
bash scripts/start-dev.sh --no-mm     # frontend only
bash scripts/start-dev.sh --mm-only   # market maker only
```

Visit http://localhost:3000

## Smart Contracts

### Core Contracts

| Contract | Description | Lines of Code |
|----------|-------------|---------------|
| `Factory.sol` | Pool deployment & management | ~170 |
| `Vault.sol` | Collateral management | ~240 |
| `Pool.sol` | Order book & matching engine | ~600 |
| `PositionNFT.sol` | ERC721 position tokens | ~250 |
| `Liquidation.sol` | Liquidation engine | ~360 |
| `IndexOracle.sol` | Price oracle & funding rate | ~285 |
| `Router.sol` | User interaction entry point | ~120 |

### Libraries

| Library | Description |
|---------|-------------|
| `IzitOSTreeMinimum.sol` | Order Statistics Tree (on-chain order book) |
| `OrderTypes.sol` | Common types and structs |
| `PosERC721.sol` | Minimal ERC721 for position NFTs |
| `PoolDeployer.sol` | Pool & engine deployment helper |
| `Ownable.sol` | Ownership management |
| `ReentrancyGuard.sol` | Reentrancy protection |

### Testing

Run tests:
```bash
forge test
forge test --match-test <name> -vv  # Run specific test with verbose output
forge test -vvvv                     # Full trace
```

## Trading Flow

### Opening a Position

1. **Deposit Collateral**
   ```solidity
   vault.deposit(1000e6);  // Deposit 1000 USDC
   ```

2. **Create Order**
   ```solidity
   PoolOrder memory order = PoolOrder({
     isSell: false,              // Long position
     oType: orderType.Limit,     // Limit order
     size: 10e6,                 // 10 units
     price: 500e6                // $500.00 (6 decimals)
   });
   pool.newOrder(1000e6, order); // 1000 USDC margin
   ```

3. **Order Matching**
   - Orders match by price-time priority
   - Maker gets 0.3% fee rebate
   - Taker pays 0.5% fee
   - Position NFT minted to trader

### Closing a Position

```solidity
PoolOrder memory closeOrder = PoolOrder({
  isSell: true,              // Close long with sell
  oType: orderType.Limit,    // Limit order
  size: 10e6,                // Close entire position
  price: 550e6               // $550.00 (6 decimals)
});
pool.closePosition(positionId, closeOrder);
```

PnL is automatically calculated and settled to trader's vault balance.

## Liquidation Mechanism

Positions are liquidated when remaining margin falls below 20% of initial margin:
```
Remaining Margin < 20% × Open Margin  →  Trigger Liquidation
```

**Two-Step Liquidation Model:**
1. **Trigger**: Anyone calls `liquidationEngine.liquidate()` — sweeps all triggered positions
2. **Action**: For each triggered position, a Limit closing order is placed at the **bankruptcy price** (where margin = 0)
3. The order enters the normal orderbook matching flow
4. If matched, PnL is settled; remaining margin (if any) returned to trader

**Price Derivation:**
- **Trigger Price**: price where remaining margin = 20% of open margin
- **Bankruptcy Price**: price where remaining margin = 0
- Both prices account for accumulated funding rate

## Security

### Audits
- [ ] Internal review completed
- [ ] External audit pending
- [ ] Bug bounty program planned

### Security Features
- Reentrancy guards on all external calls
- Access control with Ownable pattern
- Input validation on all functions
- Price staleness checks (30-minute max)
- Rate limiting on oracle updates

### Known Limitations
- Oracle dependency (centralized price feed)
- Gas costs for on-chain order book
- Limited scalability compared to off-chain order books

## Gas Optimization

Expected gas costs (at 50 gwei):

| Operation | Gas Used | Cost (ETH) | Cost (USD @ $3000) |
|-----------|----------|------------|-------------------|
| Deposit | 50,000 | 0.0025 | $7.50 |
| Order Creation | 200,000 | 0.010 | $30.00 |
| Order Matching | 300,000 | 0.015 | $45.00 |
| Close Position | 250,000 | 0.0125 | $37.50 |
| Liquidation | 150,000 | 0.0075 | $22.50 |

## Roadmap

### Phase 1: MVP (Current)
- [x] Core smart contracts
- [x] Isolated margin system
- [x] NFT-based positions
- [x] On-chain order book
- [x] Liquidation engine
- [x] Basic frontend
- [x] Oracle service
- [x] Comprehensive tests

### Phase 2: Enhancement (Q2 2026)
- [ ] Cross-margin pools
- [ ] Order types (stop-loss, take-profit)
- [ ] Advanced charting
- [ ] Mobile app
- [ ] Governance token
- [ ] Decentralized oracle (Chainlink)

### Phase 3: Scaling (Q3 2026)
- [ ] Layer 2 deployment (Arbitrum, Optimism)
- [ ] Off-chain order book with on-chain settlement
- [ ] API for trading bots
- [ ] Liquidity mining program
- [ ] Integration with CS2 marketplaces

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Workflow

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Write tests
5. Run `forge test` and ensure all pass
6. Submit a pull request

## Documentation

- [Deployment Guide](deploy/README.md) - Complete deployment instructions
- [Testing Guide](TESTING.md) - How to run and write tests
- [Frontend Guide](frontend/FRONTEND_README.md) - Frontend setup and usage
- [Market Maker Guide](marketmaker/before_start.md) - Market maker setup
- [Oracle Service Guide](oracle-service/README.md) - Oracle service setup
- [Concepts & Whitepaper](concepts/README.md) - Project background and design docs

## Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [Solidity Documentation](https://docs.soliditylang.org/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [SkinFlow.gg CS2 Indices](https://skinflow.gg/csgo-stash/graph/overview)
- [EsportFire CS2 Indices](https://esportfire.com/indexes)

## Support

- **Discord**: [Join our Discord](https://discord.gg/cs2index)
- **GitHub Issues**: [Report bugs or request features](https://github.com/yourusername/CS2InDEX/issues)
- **Email**: support@cs2index.com
- **Twitter**: [@CS2InDEX](https://twitter.com/cs2index)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This software is experimental and provided "as is". Use at your own risk. Trading perpetual futures involves significant risk and may not be suitable for all investors. Always perform your own research and consider consulting with a financial advisor.

## Acknowledgments

- Inspired by traditional crypto exchanges (Binance, OKX)
- Built with [Foundry](https://github.com/foundry-rs/foundry)
- Powered by [OpenZeppelin](https://openzeppelin.com/)
- Price data from [SkinFlow.gg](https://skinflow.gg/) and [EsportFire.com](https://esportfire.com/)
- Community feedback and contributions

---

**Built with ❤️ for the CS2 trading community**
