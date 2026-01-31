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
- **Leverage Trading** - Up to 6x leverage on positions
- **Long & Short** - Profit from both rising and falling prices
- **NFT Positions** - Each position is an ERC721 NFT (transferable)
- **On-Chain Order Book** - Red-Black Tree implementation for efficient matching

### 🔒 Risk Management
- **Isolated Margin** - Each position has independent risk
- **Automated Liquidations** - 5% maintenance margin, 2.5% liquidator reward
- **Insurance Fund** - Covers bad debt from liquidations
- **ADL (Auto-Deleveraging)** - Last resort when insurance depleted
- **Real-Time Oracle** - Continuous price feeds from external sources

### 💰 Fee Structure
- **Maker Fee**: 0.3% (liquidity providers)
- **Taker Fee**: 0.5% (liquidity takers)
- **Liquidation Fee**: 2.5% (goes to liquidators)

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
│  │ ADL Engine       │  │  ADL  Engine     │             │
│  │                  │  │                  │             │
│  │ Auto liquidate   │  │ Emergency        │             │
│  │ underwater pos.  │  │ deleveraging     │             │
│  └──────────────────┘  └──────────────────┘             │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │           CS2IndexOracle.sol                      │  │
│  │     Updated by external price feed service        │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
                           ↕
┌─────────────────────────────────────────────────────────┐
│                  Oracle Service (Node.js)                │
│                                                          │
│  Fetches prices from:                                    │
│  • SkinFlow.gg (CS2 Global & Knives Indices)            │
│  • EsportFire.com (Rifles & Gloves Indices)             │
│  • Buff163 (Fallback)                                    │
│                                                          │
│  Updates on-chain oracles every 5 minutes                │
└─────────────────────────────────────────────────────────┘
                           ↕
┌─────────────────────────────────────────────────────────┐
│              Frontend (Next.js + RainbowKit)             │
│                                                          │
│  • Wallet connection (MetaMask, WalletConnect, etc.)     │
│  • Trading interface (Long/Short, Leverage)              │
│  • Position management (Open, Close, Transfer)           │
│  • Vault management (Deposit, Withdraw)                  │
│  • Real-time market data                                 │
└─────────────────────────────────────────────────────────┘
```

## Project Structure

```
CS2InDEX/
├── src/                      # Smart contracts (Solidity)
│   ├── Vault.sol            # Collateral vault with locking
│   ├── Pool.sol             # Trading pool with order book
│   ├── PositionNFT.sol      # ERC721 position tokens
│   ├── Engine.sol           # Liquidation, ADL, Oracle
│   ├── Factory.sol          # Pool deployment & management
│   └── libraries/           # RedBlackTree, OrderTypes, etc.
│
├── test/                     # Foundry tests (87 tests)
│   ├── Vault.t.sol          # Vault tests (20)
│   ├── Pool.t.sol           # Pool tests (17)
│   ├── Engine.t.sol         # Engine tests (19)
│   ├── Factory.t.sol        # Factory tests (22)
│   ├── Integration.t.sol    # Integration tests (9)
│   └── mocks/               # Mock contracts
│
├── script/                   # Deployment scripts
│   ├── Deploy.s.sol         # Testnet deployment (with mocks)
│   └── DeployMainnet.s.sol  # Mainnet deployment (real USDC)
│
├── frontend/                 # Next.js web application
│   ├── src/
│   │   ├── app/             # Next.js App Router
│   │   ├── components/      # React components
│   │   └── config/          # Contract ABIs & addresses
│   ├── package.json
│   └── README.md
│
├── oracle-service/           # Price feed backend service
│   ├── src/
│   │   ├── index.ts         # Main service entry
│   │   ├── oracle-updater.ts     # On-chain updates
│   │   ├── price-aggregator.ts   # Fetch external prices
│   │   └── utils/           # Logger, etc.
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── README.md
│
├── deploy/                   # Deployment documentation
│   └── README.md            # Complete deployment guide
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
# Run all smart contract tests (87 tests)
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
# Edit .env with your values

# Deploy to Sepolia
forge script script/Deploy.s.sol \
  --rpc-url sepolia \
  --broadcast \
  --verify \
  -vvvv
```

See [deploy/README.md](deploy/README.md) for detailed deployment instructions.

### 5. Start Oracle Service

```bash
cd oracle-service

# Configure environment
cp .env.example .env
# Edit .env with deployed oracle addresses

# Start service
npm run dev
```

See [oracle-service/README.md](oracle-service/README.md) for detailed oracle setup.

### 6. Run Frontend

```bash
cd frontend

# Configure environment
cp .env.example .env.local
# Edit .env.local with WalletConnect Project ID

# Start development server
npm run dev
```

Visit http://localhost:3000

See [frontend/README.md](frontend/README.md) for detailed frontend guide.

## Smart Contracts

### Core Contracts

| Contract | Description | Lines of Code |
|----------|-------------|---------------|
| `Vault.sol` | Collateral management with locking | ~200 |
| `Pool.sol` | Order book & matching engine | ~400 |
| `PositionNFT.sol` | ERC721 position tokens | ~150 |
| `LiquidationEngine.sol` | Automated liquidations | ~200 |
| `ADLEngine.sol` | Auto-deleveraging | ~150 |
| `CS2IndexOracle.sol` | Price oracle | ~100 |
| `Factory.sol` | Pool deployment | ~250 |

### Libraries

| Library | Description |
|---------|-------------|
| `RedBlackTree.sol` | On-chain order book data structure |
| `OrderTypes.sol` | Common types and structs |

### Test Coverage

- **Total Tests**: 87
- **Coverage**: ~90% of core functionality
- **Categories**:
  - Unit Tests: 69
  - Integration Tests: 9
  - Authorization Tests: 9

Run tests:
```bash
forge test
forge coverage  # Generate coverage report
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
     isSell: false,      // Long position
     oType: 1,           // Limit order
     size: 10e6,         // 10 units
     priceX100: 50000,   // $500.00
     margin: 1000e6      // 1000 USDC margin
   });
   pool.newOrder(order);
   ```

3. **Order Matching**
   - Orders match by price-time priority
   - Maker gets 0.3% fee rebate
   - Taker pays 0.5% fee
   - Position NFT minted to trader

### Closing a Position

```solidity
PoolOrder memory closeOrder = PoolOrder({
  isSell: true,       // Close long with sell
  oType: 1,           // Limit order
  size: 10e6,         // Close entire position
  priceX100: 55000,   // $550.00
  margin: 0           // No additional margin
});
pool.closePosition(positionId, closeOrder);
```

PnL is automatically calculated and settled to trader's vault balance.

## Liquidation Mechanism

Positions are liquidated when:
```
Margin Ratio = Available Margin / Position Value < 5%
```

**Liquidation Process:**
1. Liquidator calls `liquidationEngine.liquidate(pool, positionId)`
2. Position is force-closed at market price
3. Liquidator receives 2.5% of position value
4. Remaining margin returned to trader (if any)
5. Deficit covered by insurance fund

**ADL (Auto-Deleveraging):**
- Triggered when insurance fund is insufficient
- Opposite positions are automatically closed
- Prioritized by profitability and leverage

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
- [Frontend Guide](frontend/README.md) - Frontend setup and usage
- [Oracle Service Guide](oracle-service/README.md) - Oracle service setup
- [Frontend Deployment](frontend/DEPLOYMENT.md) - Frontend deployment guide

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
