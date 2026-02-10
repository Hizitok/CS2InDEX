# CS2InDEX — TODO List

## 1. Code Audit (代码审计)

### 1.1 Access Control
- [ ] Verify all `onlyOwner` / `onlyFactory` / `onlyPool` modifiers cover every state-changing function
- [ ] Confirm `isMyPool` modifier logic in Factory after recent fix (`!=` vs `==`)
- [ ] Audit Router.sol `emergencyCloseAllPositions` — currently incomplete, ensure proper access control before enabling
- [ ] Check that `isPoolAuthorized` in PositionNFT correctly gates all mint/burn/update paths

### 1.2 Reentrancy & CEI
- [ ] Pool.sol `matchMaking` — verify Checks-Effects-Interactions pattern across Vault transfers, Oracle calls, NFT mints
- [ ] Pool.sol `settlePnL` — external calls to Vault after state changes, confirm ReentrancyGuard coverage
- [ ] Vault.sol `withdraw` / `withdrawTo` — ensure balance deducted before ERC20 transfer
- [ ] Liquidation.sol `liquidate()` — loops over positions with external calls to Pool, check gas limits and reentrancy

### 1.3 Integer Arithmetic
- [ ] `fundingIdx` initialized to `1 << 63` — confirm no underflow when funding rate is negative over long periods
- [ ] `pnlAmount = pnl / int256(10**pxDecimals) - 1` — protocol protection rounding, verify edge cases near zero PnL
- [ ] `openAmount / openSize` division for average entry price — verify no precision loss for small sizes
- [ ] Liquidation trigger/bankruptcy price calculations — verify against extreme leverage (close to 6x)

### 1.4 Edge Cases
- [ ] Zero-size orders, zero-price orders, zero-margin orders — all should revert cleanly
- [ ] Self-matching: trader matching against own order in orderbook
- [ ] Cancel an already-matched or partially-matched order
- [ ] Close a position that's already in `pendingClose` or `liquidating` status
- [ ] Settlement of a position with `openSize == 0` (fully cancelled before any match)
- [ ] Orderbook behavior when tree is empty (no asks or no bids)

### 1.5 Gas Optimization
- [ ] `matchMaking` loop gas profile — worst case with deep orderbook traversal
- [ ] `getPositionsByOwner` — iterates all user tokens, could be expensive for active traders
- [ ] `liquidate()` batch processing — gas limit per call, pagination strategy
- [ ] Storage slot packing review (Position struct, PoolOrder struct)

### 1.6 Upgrade & Deployment Safety
- [ ] Factory `createPool` — verify deterministic deployment with salt, no front-running of pool creation
- [ ] Confirm no `selfdestruct` or `delegatecall` in any contract
- [ ] Verify `Ownable` transfer/renounce paths are intentional

---

## 2. Standardized Oracle (更规范的预言机)

### 2.1 Current State
- IndexOracle accepts price updates from owner (Factory) only
- Single-source price feed, no on-chain validation of price reasonableness
- VTWAP calculated from matched trades within Pool
- Funding rate = clamp(VTWAP premium + interest, -200bp, +200bp)

### 2.2 Multi-Source Price Aggregation
- [ ] Design aggregator architecture: N data sources → median/weighted average → on-chain price
- [ ] Define price deviation threshold: reject updates that deviate >X% from previous price
- [ ] Implement staleness check: revert if `block.timestamp - lastUpdateTime > MAX_STALENESS`
- [ ] Add circuit breaker: pause trading if price moves >Y% in single update

### 2.3 Chainlink Integration (optional path)
- [ ] Evaluate if Chainlink has CS2 skin market data feeds
- [ ] If not, design Chainlink Functions or custom adapter for off-chain data
- [ ] Implement `AggregatorV3Interface` compatible wrapper for existing oracle
- [ ] Add roundId tracking and historical price queries

### 2.4 Decentralized Reporter Network
- [ ] Design multi-signer oracle: M-of-N reporters must agree on price within tolerance
- [ ] Implement commit-reveal scheme to prevent front-running of price updates
- [ ] Reporter staking and slashing mechanism for incorrect prices
- [ ] Reward distribution for honest reporters

### 2.5 Manipulation Resistance
- [ ] TWAP (Time-Weighted Average Price) over configurable window for funding rate calculation
- [ ] Volume-weighted aggregation to reduce impact of wash trading
- [ ] Outlier detection: reject data points beyond 3-sigma from rolling median
- [ ] Rate limiting: max price change per time window

### 2.6 Oracle Interface Improvements
- [ ] `updatePoolInfo` — add `lastTradeTimestamp` parameter for stale trade detection
- [ ] Emit events on every price update with source metadata
- [ ] Add `getOracleHealth()` view: last update time, deviation from market, confidence score
- [ ] Support multiple asset classes (future: weapon skins, stickers, cases separately)

---

## 3. Off-Chain Data Sources & Analysis (链下数据来源与分析)

### 3.1 Primary Data Sources
- [ ] **Steam Community Market API**
  - Price history endpoint: `market/pricehistory`
  - Current listings: `market/listings`
  - Rate limits: ~20 requests/minute, need caching layer
  - Limitations: only Steam market, not third-party

- [ ] **Third-Party Marketplaces**
  - Buff163 (buff.163.com) — largest CN CS2 market
  - DMarket — international marketplace with API
  - Skinport — EU market with public API
  - CSFloat — float-value focused marketplace
  - Bitskins — crypto-native skin marketplace

- [ ] **Aggregation Services**
  - CSGOBackpack / PriceEmpire — multi-source aggregated prices
  - Steam Analytics / CS2 Analyst — historical data providers

### 3.2 Data Pipeline Architecture
```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────┐
│ Data Sources│────>│  Aggregator  │────>│  Validator  │────>│  Oracle  │
│  (5+ APIs)  │     │  (Median +   │     │  (Deviation │     │  (On-    │
│             │     │   Weighting) │     │ + Staleness)│     │  Chain)  │
└─────────────┘     └──────────────┘     └─────────────┘     └──────────┘
```
- [ ] API adapter layer: normalize different marketplace APIs to common format
- [ ] Scheduling: configurable polling intervals per source (30s ~ 5min)
- [ ] Caching: Redis/in-memory cache to reduce API calls and handle rate limits
- [ ] Failover: if primary source is down, fall back to secondary sources

### 3.3 Index Composition & Calculation
- [ ] Define CS2 Market Index basket:
  - Top N most traded skins by volume (e.g. AK-47 Redline, AWP Asiimov, etc.)
  - Weighting method: equal weight vs volume-weighted vs market-cap weighted
  - Rebalancing frequency: weekly/monthly
- [ ] Index formula: `Index = Σ (weight_i × price_i) / divisor`
- [ ] Handle delistings, new skin releases, and extraordinary events (operation drops)
- [ ] Track float value ranges: Factory New / Minimal Wear / Field-Tested etc.

### 3.4 Statistical Analysis & Risk Metrics
- [ ] **Volatility Analysis**
  - Historical volatility (rolling 7d/30d/90d)
  - Implied volatility from market spread
  - Volatility smile/skew across skin categories
- [ ] **Correlation Analysis**
  - Skin-to-skin correlation matrix (do all skins move together?)
  - CS2 market vs crypto market correlation
  - Impact of game updates, major tournaments, operation releases
- [ ] **Liquidity Metrics**
  - Bid-ask spread by source
  - Order book depth
  - Volume concentration (Herfindahl index)
  - Time-to-fill analysis

### 3.5 Oracle Service Implementation
- [ ] Extend existing `oracle-service/` with multi-source fetching
- [ ] Add health monitoring dashboard (source uptime, price deviation alerts)
- [ ] Implement backfill capability for historical data gaps
- [ ] Add Prometheus metrics + Grafana dashboards for monitoring
- [ ] Dockerize with proper secrets management (API keys)

### 3.6 Data Quality & Integrity
- [ ] Cross-source price validation before publishing
- [ ] Detect and flag wash trading patterns (same buyer/seller, circular trades)
- [ ] Handle currency normalization (CNY from Buff163 → USD)
- [ ] Track and adjust for marketplace fees (Steam 15%, Buff 2.5%, etc.)
- [ ] Log all raw data for audit trail and backtesting

---

## Priority Order

| Phase | Task | Dependency |
|-------|------|-----------|
| **P0** | Code Audit §1.1-1.4 | Before mainnet |
| **P1** | Off-chain Data Pipeline §3.1-3.2 | Oracle needs data |
| **P1** | Index Composition §3.3 | Defines what oracle publishes |
| **P2** | Standardized Oracle §2.2-2.3 | Needs data pipeline |
| **P2** | Statistical Analysis §3.4 | Needs historical data |
| **P3** | Decentralized Reporters §2.4 | After MVP proven |
| **P3** | Oracle Service Monitoring §3.5 | Production readiness |
