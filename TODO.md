# CS2InDEX — TODO List

## 1. Code Audit (代码审计)
> **Audit completed 2026-02-24.** All CRITICAL/HIGH/MEDIUM bugs fixed; remaining items are LOW/design decisions.

### 1.1 Access Control
- [x] Verify all `onlyOwner` / `onlyFactory` / `onlyPool` modifiers cover every state-changing function — **PASS**
- [x] Confirm `isMyPool` modifier logic in Factory — **PASS** (`factory == address(this)` check is correct)
- [ ] Router.sol `emergencyCloseAllPositions` — body is empty (just emits event); **do not enable** until fully implemented
- [x] `isPoolAuthorized` in PositionNFT gates all mint/update/settle paths via `onlyPool` — **PASS**

### 1.2 Reentrancy & CEI
- [x] Pool.sol `matchMaking` — all external calls (positionNFT, engine, oracle, vault) use trusted contracts deployed by Factory; no untrusted call paths; Pool lacks `nonReentrant` but risk is low with trusted contracts — **ACCEPTABLE**
- [x] Pool.sol `settlePnL` — `internalTransfer` moves vault-internal balances only (no ERC20 `transfer` to caller), so no reentrancy entry point — **PASS**
- [x] Vault.sol `withdraw` / `withdrawTo` — balance decremented before ERC20 transfer (CEI correct) — **PASS**
- [ ] Liquidation.sol `liquidate()` — unbounded loop; no gas limit guard → **potential block gas exhaustion in cascade liquidations** (see §1.5)

### 1.3 Integer Arithmetic
- [x] `fundingIdx = 1 << 63` initialization — initial offset cancels in PnL calculation; no underflow risk at realistic position sizes — **PASS**
- [x] `pnlAmount = pnl / 10**pxDecimals - 1` — intentional conservative rounding; -1 unit is negligible vs any real position — **PASS**
- [x] `openAmount / openSize` — guarded with `openSize == 0` check — **PASS**
- [x] Liquidation trigger/bankruptcy prices — `_calcRelativePxAtLoss` uses int256 arithmetic; no overflow at 6x leverage — **PASS**
- [x] **FIXED** `calculateFundingRate` uint128 underflow (bearish VTWAP < oracle) and div/0 (no samples) — **FIXED**
- [x] **FIXED** VTWAP accumulator `uint128(price) * VTWeight` overflow → trade DoS — **FIXED**

### 1.4 Edge Cases
- [x] **FIXED** Zero-size / zero-margin orders — now revert with `InvalidOrder()` — **FIXED**
- [ ] Self-matching — trader can match own buy+sell orders to inflate VTWAP oracle; costs fees but distorts funding rate — **KNOWN RISK** (mitigation: off-chain monitoring)
- [x] Cancel partially-matched order — proportional refund is correct — **PASS**
- [x] Close position in `pendingClose` / `liquidating` — both revert with `InvalidStatus` — **PASS**
- [x] **FIXED** Market orders with unfilled remainder — margin was permanently trapped; now auto-cancelled — **FIXED**
- [x] Empty orderbook (no asks/bids) — `getMin`/`getMax` returns 0, loop breaks — **PASS**

### 1.5 Gas Optimization
- [ ] `liquidate()` loop — no iteration cap; **add a `maxIterations` parameter** to prevent block gas exhaustion
- [ ] `getPositionsByOwner` — O(totalSupply) scan; **expensive for active traders** — consider off-chain indexing
- [ ] `matchMaking` loop — bounded by open orders; acceptable for current scale
- [ ] Storage packing — Position struct is 12 fields across many slots; acceptable tradeoff for readability

### 1.6 Upgrade & Deployment Safety
- [x] Factory `createPool` uses regular `new` (no CREATE2); no salt front-running risk since only owner can call — **PASS**
- [x] No `selfdestruct` or `delegatecall` in any contract — **PASS**
- [x] `Ownable` — standard OZ pattern; owner is deployer; no renounce called — **PASS**
- [ ] Router.sol `depositAndOpenPosition` — Router calls `vault.internalTransfer` but Router is not authorized in Vault (`availablePools[router] = false`); **Router is currently non-functional** — needs `vault.setPool(router, true)` in Factory setup

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
