# CS2Index

[English](README.md) | [简体中文](README.zh-CN.md)

**On-Chain Perpetual Futures for Game Item Market Indices**  
**面向游戏饰品价格指数的链上永续合约协议**

CS2Index is a fully on-chain perpetual futures exchange for CS2 (Counter-Strike 2) item market indices. Traders can go long or short with up to 10x leverage, settle entirely in USDC, and gain exposure without having to custody the underlying game assets.

CS2Index 将 CS2（Counter-Strike 2）饰品价格指数带入链上永续合约体系。用户可以用最高 10x 杠杆围绕指数做多或做空，以 USDC 结算，并且无需托管任何底层游戏道具。

> **Deployed on:** Unichain Sepolia (testnet)
> **Mainnet target:** Unichain Mainnet (planned for Q2 2026)
> **中文完整文档:** [README.zh-CN.md](README.zh-CN.md)

---

## Overview
**项目概览**

CS2Index turns the multi-billion-dollar CS2 skin economy into a 24/7, cash-settled, on-chain derivatives market. It addresses the core frictions of today's skin economy: Steam lockups, unilateral trade cancellations, fragmented off-platform liquidity, and the absence of hedging tools.

CS2Index 正在把数十亿美元规模的 CS2 饰品经济升级为一个 24/7 可交易、以 USDC 结算、完全链上可验证的衍生品市场。它解决的是当前饰品经济里的几个核心痛点：Steam 锁仓、单边毁约、场外流动性割裂，以及缺失的对冲工具。

## Audience
**目标用户**

| Audience | What they need | What CS2Index unlocks |
|----------|----------------|------------------------|
| Skin holders and trading studios / 饰品持有者与工作室 | Hedge inventory during lock periods and volatile markets | On-chain short exposure without handling physical inventory |
| Market makers and professional traders / 做市商与专业交易者 | Transparent execution, deterministic pricing, composable positions | A fully on-chain order book with isolated margin and NFT positions |
| Crypto-native users / 加密原生用户 | Access to game-economy beta without learning item delivery workflows | USDC-settled index exposure instead of skin custody |
| Wallets, communities, and data products / 钱包、社区与数据产品 | New primitives to integrate, analyze, or distribute | Index rails, order-book data, and transferable position NFTs |

## Value Proposition
**项目价值**

- **Real hedging for virtual goods**: Adds short exposure and perpetuals to a market that is still dominated by spot-only risk.
- **No asset custody**: The protocol never holds in-game items, reducing operational and compliance friction.
- **Verifiable market structure**: Matching, funding, liquidation, and settlement happen fully on-chain.
- **Capital-efficient access**: Users trade item indices with USDC margin instead of sourcing or warehousing skins.
- **Composable infrastructure**: Positions are ERC-721 NFTs that can be transferred, integrated, or extended by downstream products.

- **为虚拟商品提供真实对冲能力**：把做空和永续合约引入目前仍以现货风险为主的游戏饰品市场。
- **不托管游戏资产**：协议不接触实物饰品，降低运营与合规摩擦。
- **市场结构可验证**：撮合、资金费、清算、结算全部发生在链上。
- **更高资金效率**：用户以 USDC 保证金交易指数，而不是采购和囤积实物饰品。
- **更强可组合性**：仓位是 ERC-721 NFT，可被转移、集成和二次开发。

## Repo Guide
**阅读方式**

- English technical documentation continues below in this file.
- 完整中文版本请见 [README.zh-CN.md](README.zh-CN.md)。

## Table of Contents

- [Overview](#overview)
- [Audience](#audience)
- [Value Proposition](#value-proposition)
- [Repo Guide](#repo-guide)
- [Why CS2Index](#1-why-gameidex)
- [How It Works](#2-how-it-works)
- [Architecture](#3-architecture)
- [Contract Reference](#4-contract-reference)
- [Order Book Design](#5-order-book-design)
- [Position Lifecycle](#6-position-lifecycle)
- [Funding Rate Mechanism](#7-funding-rate-mechanism)
- [Margin & Liquidation](#8-margin--liquidation)
- [Fee Structure](#9-fee-structure)
- [Key Parameters](#10-key-parameters)
- [Getting Started](#11-getting-started)
- [Deployment](#12-deployment)
- [Security](#13-security)

---

## 1. Why CS2Index

### The Problem: A $5B Market with No Hedging Tools

The CS2 skin market is one of the largest virtual item economies in the world, with an estimated market cap of **$5–8 billion** and over **35 million active players**. Annual trading volume across Steam and third-party platforms (Buff163, SkinFlow, EsportFire) exceeds $3–5 billion.

Despite this scale, skin holders have **no way to hedge**:

- **No short-selling mechanism** — traders cannot profit from (or protect against) price declines
- **No derivatives market** — there is no futures or options market for skin assets
- **Steam T+7 lock** — after a trade executes, the item is locked for 7 days and either party can cancel, exposing both sides to unhedgeable price risk

**Example exposure scenarios:**

```
You buy a knife at $500. The T+7 lock begins.
  Day 4 — market drops 20%. The knife is now worth $400.
  Day 7 — lock expires. You've taken a $100 loss with no hedge available.
```

```
You buy a knife at $500. Prices spike 30% on Day 1.
  Day 3 — the seller cancels the trade and reclaims the item.
  Result: you never owned the knife during the rally, and you have no recourse.
```

### The Solution: Index Perpetuals, On-Chain

CS2Index provides a **24/7 tradeable, USDC-settled perpetual contract** on CS2 item price indices. Key properties:

| Property | Description |
|----------|-------------|
| No custody | The protocol never holds any in-game items |
| Cash-settled | All P&L is settled in USDC |
| Permissionless | Global access, no KYC required |
| Fully on-chain | Order book, matching, and settlement are all on-chain and verifiable |
| Composable | Positions are ERC-721 NFTs that can be transferred or sold |

**Available Indices (initial):**

| Index | Coverage |
|-------|----------|
| CS2 Global Index | Full market (~$5B cap) |
| CS2 Knives Index | Knife skins (~$700M cap) |
| CS2 Rifles Index | Rifle weapon skins |
| CS2 Gloves Index | Glove skins |

---

## 2. How It Works

```
User deposits USDC into Vault
          │
          ▼
User places order (Long/Short, Limit/Market) via Pool
          │
          ▼
On-chain Order Statistics Tree matches the order
          │
          ├── No match → order rests in the order book
          │
          └── Match found → Position NFT minted to user's wallet
                    │
                    ▼
          Funding rate settled every 8 hours (VTWAP-based)
                    │
                    ▼
          User closes position, or liquidation triggered at trigger price
                    │
                    ▼
          USDC P&L settled back to Vault
```

---

## 3. Architecture

The protocol is composed of six contracts deployed by a central Factory:

```
Factory
  ├── Vault              (USDC margin custody)
  ├── Pool               (order book + matching engine)
  ├── PositionNFT        (ERC-721 position tokens)
  ├── LiquidationEngine  (automated liquidation)
  └── IndexOracle        (price feed + funding rate)
```

**Key design decisions:**

- **Isolated margin per position** — losses in one position cannot affect another
- **Order Statistics Tree** — O(log n) order book with no AMM slippage
- **VTWAP oracle** — manipulation-resistant, time-and-volume weighted price
- **Global `fundingIdx` accumulator** — O(1) funding payment calculation per position, regardless of total position count
- **NFT positions** — every filled position is an ERC-721 token; positions can be transferred and traded

---

## 4. Contract Reference

### `Factory.sol`

The system deployer and owner. Responsible for:
- Deploying new trading pairs (Pool + Engine) via `createPool(name, initialPrice, pxDecimals)`
- Holding ownership of Oracle and Vault (`owner = address(factory)`)
- Maintaining the list of authorized pools
- Setting global parameters (fee rates, leverage cap)
- Relaying oracle price updates via `updatePrice(pool, price)`

### `Vault.sol`

Sole custody point for all USDC. Handles:
- User `deposit` and `withdraw`
- Internal balance accounting (`balances` mapping)
- `internalTransfer(from, to, amount)` — moves funds between accounts without touching external contracts, eliminating re-entrancy surface

No ERC-20 transfer occurs during a trade; all P&L flows through `internalTransfer`.

### `Pool.sol`

The core order book and matching engine. Handles:
- Accepting `newOrder(margin, PoolOrder)` — limit or market, buy or sell
- Running the price-time-priority matching loop against the Order Statistics Tree
- Collecting maker/taker fees and transferring them to the protocol fee account
- Updating the VTWAP accumulator in Oracle after each fill
- Minting/updating/burning Position NFTs via PositionNFT
- Registering new positions with LiquidationEngine

### `PositionNFT.sol`

ERC-721 contract where each token represents one trading position.

```solidity
struct Position {
    bool     isShort;           // true = short, false = long
    posStatus status;           // pendingOpen / open / closed / settled
    uint256  openMargin;        // deposited margin (USDC, 6 decimals)

    uint128  pendingSize;       // unfilled order quantity
    uint128  openSize;          // filled position size
    uint128  closeSize;         // quantity closed so far
    uint128  openAmount;        // cumulative fill value (price × size)
    uint128  closeAmount;       // cumulative close value
    uint128  openFundingIdx;    // global fundingIdx snapshot at open
    uint128  closeFundingIdx;   // global fundingIdx snapshot at close
}
```

Position NFTs are standard ERC-721 tokens and can be transferred, listed, or sold on any NFT marketplace. Transferring a position NFT transfers ownership of the underlying position.

### `LiquidationEngine.sol`

Automated liquidation monitor. Responsibilities:
- Maintains a sorted queue of all open positions ordered by their liquidation trigger price (using an Order Statistics Tree)
- Exposes a permissionless `liquidate()` function that any account can call to execute pending liquidations
- Calculates `triggerPrice` and `bankruptcyPrice` for each position
- Places liquidation close orders into the Pool's order book at bankruptcy price

### `IndexOracle.sol`

Price feed and funding rate settlement. Provides:
- On-chain storage of the off-chain index price (updated by the Factory-authorized reporter every ~5 minutes)
- VTWAP accumulator — updated by Pool after every fill
- Funding rate calculation via `calculateFundingRate(pool)`
- Funding rate application via `applyFundingRate(pool)` — callable every 8 hours
- Global `fundingIdx` accumulator maintenance
- Price staleness detection (trading halted if price not updated in 30 minutes)

---

## 5. Order Book Design

### Order Statistics Tree

The order book is implemented as an **Order Statistics Tree (OST)** — an augmented red-black tree where each node stores the subtree size, enabling O(log n) rank queries.

| Operation | Complexity |
|-----------|------------|
| Insert | O(log n) |
| Delete | O(log n) |
| Get min/max price | O(log n) |
| Count orders below price | O(log n) |

Two separate OST instances are maintained per pool: one for bids and one for asks.

### Order Matching

Matching follows **price-time priority**:

| Order type | Matching rule |
|------------|---------------|
| Market buy | Fills against lowest-priced ask(s) until fully filled or book exhausted |
| Market sell | Fills against highest-priced bid(s) until fully filled or book exhausted |
| Limit buy | If best ask ≤ limit price → fills immediately (taker); otherwise rests in bid tree (maker) |
| Limit sell | If best bid ≥ limit price → fills immediately (taker); otherwise rests in ask tree (maker) |

Partial fills are supported. A position in `pendingOpen` status remains in the order book until fully matched or cancelled.

### On-Chain Order Book vs AMM

| Dimension | AMM (e.g. Uniswap V3) | CS2Index (order book) |
|-----------|-----------------------|------------------------|
| Limit orders | Not supported | Native support |
| Price slippage | Grows with trade size | Zero slippage on limit orders |
| Execution certainty | Depends on liquidity curve | Price-deterministic |
| Market depth visibility | Implicit | Explicit, fully on-chain |
| Best fit for | High-frequency spot | Derivatives, professional trading |

---

## 6. Position Lifecycle

### State Machine

```
pendingOpen  ←─ order placed (unfilled)
     │
     │  order matched
     ▼
   open  ──────────────────────────────┐
     │                                 │
     │  user requests close            │  price crosses triggerPrice
     ▼                                 ▼
pendingClose                      liquidating
     │                                 │
     │  close order matched            │  liquidation order matched
     ▼                                 ▼
  closed ◄────────────────────────────┘
     │
     │  P&L settled to Vault, NFT burned
     ▼
 settled
```

### State Descriptions

| Status | Description |
|--------|-------------|
| `pendingOpen` | Order submitted, waiting for a counterparty match |
| `open` | Position fully (or partially) matched and active |
| `pendingClose` | Close order submitted, waiting for match |
| `liquidating` | Trigger price breached; liquidation order placed in book |
| `closed` | Close order matched; P&L calculated |
| `settled` | P&L paid to Vault; NFT burned |

If a `pendingClose` position also hits its trigger price, the system prioritizes liquidation to prevent users from evading forced closure by placing an unreachable close price.

---

## 7. Funding Rate Mechanism

Funding rates anchor the perpetual contract price to the index price by transferring payments between long and short holders every 8 hours.

### Formula

```
fundingRate = clamp(premiumIndex + interestRate, −maxFR, +maxFR)
```

| Parameter | Value | Description |
|-----------|-------|-------------|
| `premiumIndex` | Dynamic | `(VTWAP − oraclePrice) / oraclePrice × 10000` (in bp) |
| `interestRate` | 100 bp (1%) | Fixed base rate, incentivizes short-side market makers |
| `maxFR` | 200 bp (2%) | Per-period funding rate cap |
| `fundingPeriod` | 8 hours | Settlement interval |

**Economic effect:**
- When VTWAP > oracle price (longs trading at a premium), longs pay shorts
- When VTWAP < oracle price (shorts trading at a premium), shorts pay longs
- The fixed `interestRate` provides a baseline incentive for liquidity providers

### VTWAP Calculation

Each fill contributes to the VTWAP with weight:

```
weight_i = min(Δt_i, 3600) × size_i
```

where `Δt_i` is seconds since the previous fill and `size_i` is the fill's USDC notional. The 1-hour cap on `Δt` prevents a single trade after a long quiet period from dominating the VTWAP.

```
VTWAP = Σ(price_i × weight_i) / Σ(weight_i)
```

**Manipulation cost:** A wash-trader must pay `(0.3% + 0.5%) × 2 = 1.6%` per dollar of notional traded to move VTWAP. Subsequent legitimate trades dilute the attack over time.

### `fundingIdx` Global Accumulator

To avoid O(n) per-position settlement, the protocol uses a global accumulator:

```
fundingIdx  +=  fundingRate × oraclePrice    (every 8 hours)
```

Each position stores its `openFundingIdx` snapshot at open time. Funding payment at close:

```
fundingPayment = openSize × (fundingIdx_close − fundingIdx_open)
```

- Long position: positive payment = longs owe shorts (deducted from margin)
- Short position: positive payment = shorts receive from longs (added to margin)

`fundingIdx` is initialized to `0` and uses additive accumulation, avoiding Q128 precision overflow.

---

## 8. Margin & Liquidation

### Isolated Margin

Every position uses **isolated margin**: each position's collateral is independent. A loss on one position cannot cascade to another. Maximum loss per position is capped at the margin deposited for that position.

### Trigger Price (Liquidation Threshold)

**Long position trigger price:**

```
triggerPrice_long = entryPrice × (1 − (1 − maintenanceMarginRatio) / leverage)
```

**Short position trigger price:**

```
triggerPrice_short = entryPrice × (1 + (1 − maintenanceMarginRatio) / leverage)
```

Where `maintenanceMarginRatio = 20%`.

**Example (5x leverage long, entry at $100):**

```
triggerPrice = 100 × (1 − (1 − 0.20) / 5) = 100 × 0.84 = $84
```

The trigger price is affected by cumulative funding payments. As funding accumulates against a position, the effective trigger price moves toward the current market price, eventually triggering liquidation even without a price move.

### Bankruptcy Price

The price at which margin is exactly zero:

```
bankruptcyPrice_long  = entryPrice × (1 − 1/leverage)
bankruptcyPrice_short = entryPrice × (1 + 1/leverage)
```

### Two-Step Liquidation

**Step 1 — Trigger scan (permissionless):**

Anyone can call `LiquidationEngine.liquidate()`. The engine walks the sorted position queue and identifies positions where the oracle price has crossed `triggerPrice`.

**Step 2 — Order book close:**

For each triggered position:
1. Position status set to `liquidating`
2. A close limit order placed in Pool at `bankruptcyPrice`
3. Liquidation bonus deducted from remaining margin
4. PositionNFT status updated

**Step 3 — Normal matching:**

The liquidation close order enters the standard order book. When matched:
1. P&L calculated including funding payments and fees
2. Net proceeds settled to the former position holder's Vault balance
3. NFT burned; position moves to `settled`

---

## 9. Fee Structure

| Fee type | Rate | Description |
|----------|------|-------------|
| Maker fee | 0.3% | Paid by the order that rests in the book |
| Taker fee | 0.5% | Paid by the order that triggers a match |
| Funding rate | ±2% per 8h (cap) | Paid between longs and shorts; does not go to the protocol |

Fees are denominated in USDC and deducted from the fill amount via `Vault.internalTransfer`. The maker-taker spread (0.2%) rewards liquidity providers and discourages excessive market-order usage.

---

## 10. Key Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| `MAKERFEE` | `3000` → 0.3% | `amount × 3000 / 1e6` |
| `TAKERFEE` | `5000` → 0.5% | `amount × 5000 / 1e6` |
| `maxLeverage` | `1000` → 10x | Stored as `leverage × 100` |
| Maintenance margin | 20% | Triggers liquidation when margin < 20% of position value |
| `fundingPeriod` | 28 800 s (8 h) | Settlement interval |
| `maxFundingRate` | 200 bp (2%) | Per-period cap |
| `interestRate` | 100 bp (1%) | Fixed base rate added to premiumIndex |
| `pxDecimals` | 6 | Price precision aligned with USDC |
| Oracle stale threshold | 1 800 s (30 min) | New orders rejected if oracle is stale |
| VTWAP time cap | 3 600 s (1 h) | `min(Δt, 3600)` per fill weight |

---

## 11. Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`)

### Install

```bash
git clone https://github.com/izit1/CS2Index.git
cd CS2Index
forge install
```

### Build

```bash
forge build
```

### Run Tests

```bash
# Run all tests
forge test

# Run with verbose output (see logs)
forge test -vv

# Run a specific test
forge test --match-test testFullTradingFlow -vv

# Full trace (debug mode)
forge test --match-test testLiquidationEngine -vvvv

# Gas benchmark
forge test --match-test testGasBenchmark_1000Orders -vv
```

### Test Coverage

```bash
forge coverage
```

The test suite includes:

| Test file | Coverage |
|-----------|----------|
| `Integration.t.sol` | Full trading flow, oracle updates, orderbook depth, vault ops, order cancellation, partial fills, funding rate settlement, liquidation engine, crossed book matching, liquidation diagnostics |
| `GasBenchmark.t.sol` | 2000-order stress test with gas distribution reporting |
| `InternalGasTest.t.sol` | Compiler optimization analysis |

---

## 12. Deployment

### Configuration

Pool parameters are defined in [`deploy/pools.config.json`](deploy/pools.config.json):

```json
[
  { "name": "CS2 Global Index",  "initialPrice": 393500000, "pxDecimals": 6 },
  { "name": "CS2-Knives-Index",  "initialPrice":  80000000, "pxDecimals": 6 },
  { "name": "CS2-Rifles-Index",  "initialPrice":  30000000, "pxDecimals": 6 },
  { "name": "CS2-Gloves-Index",  "initialPrice":  40000000, "pxDecimals": 6 }
]
```

> Raw price = actual price × 10^pxDecimals — e.g. $393.50 → `393500000`

To add or modify pools, edit this JSON file only — no Solidity changes required.

### Environment Variables

Copy the example file and fill in your values:

```bash
cp deploy/.env.example deploy/.env
```

```bash
PRIVATE_KEY=0x...          # Deployer private key
USDC_ADDRESS=0x...         # Leave blank on testnet (auto-deploys MockUSDC)
DEPLOYER_MINT=1000000000000 # USDC to mint to deployer on testnet (optional)
```

### Deploy to Testnet

```bash
forge script deploy/Deploy.s.sol \
  --rpc-url <YOUR_RPC_URL> \
  --broadcast \
  --verify \
  -vvvv
```

### Deploy to Mainnet

```bash
USDC_ADDRESS=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 \
forge script deploy/Deploy.s.sol \
  --rpc-url <MAINNET_RPC_URL> \
  --broadcast \
  --verify \
  --slow \
  -vvvv
```

Deployment addresses are written to `deploy/deployed.<chainId>.json`.

### Deployment Output

```
[MockUSDC]  deployed: 0x...
[Factory]   deployed: 0x...
[Vault]     deployed: 0x...
[Oracle]    deployed: 0x...
[NFT]       deployed: 0x...
[Pool]      CS2 Global Index
            pool  : 0x...
            engine: 0x...
[Router]    deployed: 0x...
```

---

## 13. Security

### Access Control

| Contract | Owner | Authorized callers |
|----------|-------|--------------------|
| Oracle | Factory | Factory (price updates, funding settlement) |
| Vault | Factory | Factory-authorized Pools and Router |
| Pool | Factory | Any user (public order functions) |
| PositionNFT | Pool | Pool (mint/update/burn); NFT holder (transfer) |
| LiquidationEngine | Factory | Anyone (`liquidate()` is permissionless) |

### Reentrancy

`Vault.internalTransfer` modifies only the in-memory `balances` mapping and makes no external calls, eliminating reentrancy surface from fund movements. The public `withdraw` path follows the Checks-Effects-Interactions pattern.

### Oracle Manipulation

- VTWAP uses `min(Δt, 3600) × size` weighting — wash-trade cost is **1.6% per dollar** of VTWAP manipulation
- Multi-source off-chain aggregation (SkinFlow + EsportFire + Buff163) with median filtering
- 30-minute staleness threshold halts new orders if the oracle goes silent
- VTWAP and oracle price are independent signals that cross-validate each other

### Known Limitations

| Risk | Status |
|------|--------|
| No insurance fund for bad debt | To be added (Q2 2026) |
| Single oracle reporter key | Multi-reporter network planned (Q3 2026) |
| No upgrade mechanism (non-proxy) | UUPS proxy evaluation in progress |
| Liquidation loop gas limit | `maxIterations` parameter to be added |

### Audit Status

Internal audit completed — 6 critical/high bugs found and fixed (Q1 2026). External audit scheduled.

---

## License

[MIT](LICENSE)

---

## Contributing

Issues and pull requests are welcome. For significant changes please open a discussion first.

Contracts are in [`src/`](src/). Tests are in [`test/`](test/). Deployment scripts are in [`deploy/`](deploy/).

---

## Support

If you find this project useful, consider supporting development:

| Network | Address |
|---------|---------|
| BTC | `bc1pjd7gc79yw7fqek9w6fwlkw28ad52vu8v90s4vy9d52g5pja2nn5sp56kqn` |
| ETH / ERC-20 | `0xd799eba64aaf9cfd2169afc9685494a61d23012d` |
