# CS2InDEX Oracle Service

Backend service that fetches CS2 item index prices from external sources and updates on-chain oracles.

## Overview

The Oracle Service is a critical component of the CS2InDEX protocol that:
- Fetches real-time CS2 index prices from trusted sources (SkinFlow.gg, EsportFire.com)
- Updates on-chain oracle contracts with latest prices
- Runs continuously with automated price updates
- Handles failover between multiple price sources

## Features

- **Multi-Source Price Aggregation**: Fetches from multiple APIs with fallback
- **Automated Updates**: Configurable update intervals (default: 5 minutes)
- **Price Validation**: Only updates when price changes > 0.1%
- **Rate Limiting**: Minimum 1-minute interval between updates
- **Comprehensive Logging**: Winston logger with file rotation
- **Error Handling**: Graceful handling of API failures
- **Gas Optimization**: Conservative gas limits for transactions

## Prerequisites

- Node.js v18+ and npm
- Deployed CS2InDEX contracts with oracle addresses
- RPC URL (Alchemy, Infura, or custom)
- Private key for price feeder account (with ETH for gas)

## Installation

```bash
cd oracle-service
npm install
```

## Configuration

1. **Copy environment template:**
   ```bash
   cp .env.example .env
   ```

2. **Configure environment variables:**
   ```env
   # RPC endpoint
   RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR-API-KEY

   # Price feeder wallet (needs ETH for gas)
   PRICE_FEEDER_PRIVATE_KEY=0x...

   # Oracle contracts (from deployment output)
   ORACLE_ADDRESSES='[
     {
       "name": "CS2 Global Index",
       "address": "0x1234...",
       "source": "global-index"
     },
     {
       "name": "CS2 Knives Index",
       "address": "0x5678...",
       "source": "knives-index"
     }
   ]'

   # Update interval (minutes)
   UPDATE_INTERVAL_MINUTES=5

   # Logging
   LOG_LEVEL=info
   ```

3. **Oracle Configuration Fields:**
   - `name`: Human-readable name for logging
   - `address`: Deployed oracle contract address
   - `source`: Price source identifier (must match PriceAggregator sources)

**Available Sources:**
- `global-index` - CS2 Global Index (~$4M market cap)
- `knives-index` - CS2 Knives Index (~$709K market cap)
- `rifles-index` - CS2 Rifles Index (~$150K market cap)
- `gloves-index` - CS2 Gloves Index (~$250K market cap)

## Running the Service

### Development Mode

```bash
# Run with auto-reload on file changes
npm run dev

# Or with ts-node directly
npm run watch
```

### Production Mode

```bash
# Build TypeScript to JavaScript
npm run build

# Start the service
npm start

# Or use PM2 for process management
pm2 start dist/index.js --name cs2index-oracle
pm2 save
pm2 startup
```

## Architecture

```
┌─────────────────────────────────────────┐
│         Oracle Service (Node.js)         │
├─────────────────────────────────────────┤
│                                          │
│  ┌────────────────────────────────────┐ │
│  │      Price Aggregator              │ │
│  │  ┌──────────────────────────────┐  │ │
│  │  │ SkinFlow.gg API              │  │ │
│  │  │ EsportFire.com API           │  │ │
│  │  │ Buff163 API (fallback)       │  │ │
│  │  └──────────────────────────────┘  │ │
│  └────────────────────────────────────┘ │
│                  ↓                       │
│  ┌────────────────────────────────────┐ │
│  │      Oracle Updater                │ │
│  │  ┌──────────────────────────────┐  │ │
│  │  │ Price Validation             │  │ │
│  │  │ Transaction Management       │  │ │
│  │  │ Gas Optimization             │  │ │
│  │  └──────────────────────────────┘  │ │
│  └────────────────────────────────────┘ │
│                  ↓                       │
└──────────────────│──────────────────────┘
                   │
                   ↓
        ┌──────────────────────┐
        │   Ethereum Network    │
        ├──────────────────────┤
        │ CS2IndexOracle.sol   │
        │ (on-chain contracts) │
        └──────────────────────┘
```

## Price Sources

### Primary Sources

1. **SkinFlow.gg** (https://skinflow.gg/csgo-stash/graph/overview)
   - CS2 Global Index
   - CS2 Knives Index
   - Individual items

2. **EsportFire.com** (https://esportfire.com/indexes)
   - CS2 Rifles Index
   - CS2 Gloves Index

3. **Buff163** (fallback)
   - Alternative source for all indices

### Price Update Logic

The service updates prices when:
- Price change > 0.1% from current on-chain price
- Time since last update > 1 minute
- Update interval reached (default 5 minutes)

## Monitoring

### Logs

Logs are written to:
- `logs/combined.log` - All logs (info, warn, error)
- `logs/error.log` - Error logs only
- Console - Real-time output with colors

### Log Levels

Set `LOG_LEVEL` environment variable:
- `error` - Only errors
- `warn` - Warnings and errors
- `info` - General information (default)
- `debug` - Detailed debugging

### Sample Log Output

```
2026-01-23 14:30:00 [info] 🚀 Starting CS2InDEX Oracle Service...
2026-01-23 14:30:00 [info] 🔑 Price feeder address: 0x1234...
2026-01-23 14:30:00 [info] 📊 Configured 4 oracle(s)
2026-01-23 14:30:05 [info] 📈 Starting price update cycle...
2026-01-23 14:30:06 [debug] 📊 Global Index (SkinFlow): $4,001,840.98
2026-01-23 14:30:06 [debug] 📤 Sending price update: 400184098
2026-01-23 14:30:12 [info] ✅ Updated CS2 Global Index: $4,001,840.98 (tx: 0xabc...)
2026-01-23 14:30:15 [info] ✨ Price update cycle completed
2026-01-23 14:30:15 [info] ⏰ Scheduled price updates every 5 minutes
```

## Error Handling

### Common Errors

1. **API Failures**
   - Automatically falls back to mock data
   - Logs warning and continues

2. **Transaction Failures**
   - Logs error with details
   - Retries on next cycle

3. **Authorization Errors**
   - Verifies price feeder address matches oracle configuration
   - Exits if unauthorized

4. **Gas Estimation Errors**
   - Uses conservative gas limit (100k)
   - Logs warning if gas price is high

## Gas Costs

Typical gas usage per oracle update:
- `updatePrice()`: ~50,000 gas
- At 50 gwei: ~0.0025 ETH per update
- 4 oracles × 288 updates/day = 1,152 updates/day
- Daily cost: ~2.88 ETH at 50 gwei

**Optimization Tips:**
- Increase `UPDATE_INTERVAL_MINUTES` to reduce frequency
- Set higher price change threshold (modify `priceDiffPercent`)
- Use Layer 2 for lower gas costs

## Deployment

### Using PM2 (Recommended)

```bash
# Install PM2 globally
npm install -g pm2

# Build the service
npm run build

# Start with PM2
pm2 start dist/index.js --name cs2index-oracle

# View logs
pm2 logs cs2index-oracle

# Monitor
pm2 monit

# Auto-restart on reboot
pm2 startup
pm2 save
```

### Using Docker

```dockerfile
# Dockerfile
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .
RUN npm run build

CMD ["node", "dist/index.js"]
```

```bash
# Build and run
docker build -t cs2index-oracle .
docker run -d --name oracle --env-file .env cs2index-oracle
```

### Using systemd

```ini
# /etc/systemd/system/cs2index-oracle.service
[Unit]
Description=CS2InDEX Oracle Service
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/cs2index-oracle
EnvironmentFile=/home/ubuntu/cs2index-oracle/.env
ExecStart=/usr/bin/node /home/ubuntu/cs2index-oracle/dist/index.js
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable cs2index-oracle
sudo systemctl start cs2index-oracle
sudo systemctl status cs2index-oracle
```

## Security

### Best Practices

1. **Private Key Security**
   - Never commit `.env` to git
   - Use hardware wallet or KMS in production
   - Rotate keys regularly

2. **Price Feeder Wallet**
   - Keep only enough ETH for gas
   - Monitor balance and set alerts
   - Use separate wallet from deployer

3. **API Security**
   - Use API keys when available
   - Implement rate limiting
   - Validate all external data

4. **Access Control**
   - Restrict oracle updater to authorized addresses
   - Use multi-sig for critical changes
   - Monitor all price updates

## Monitoring & Alerts

### Health Checks

Add monitoring for:
- Service uptime
- Successful update rate
- Gas costs
- Price staleness
- API availability

### Example: Prometheus Metrics

```typescript
// Add to oracle-updater.ts
import promClient from 'prom-client';

const updateCounter = new promClient.Counter({
  name: 'oracle_updates_total',
  help: 'Total oracle price updates',
});

const updateGauge = new promClient.Gauge({
  name: 'oracle_last_price',
  help: 'Last updated oracle price',
  labelNames: ['oracle_name'],
});
```

## Troubleshooting

### Service won't start

```bash
# Check logs
tail -f logs/error.log

# Verify environment variables
node -e "require('dotenv').config(); console.log(process.env)"

# Test RPC connection
curl -X POST $RPC_URL -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### Price updates failing

```bash
# Check price feeder balance
cast balance $PRICE_FEEDER_ADDRESS --rpc-url $RPC_URL

# Verify oracle authorization
cast call $ORACLE_ADDRESS "priceFeeder()(address)" --rpc-url $RPC_URL

# Check last update time
cast call $ORACLE_ADDRESS "lastUpdateTime()(uint256)" --rpc-url $RPC_URL
```

### High gas costs

```bash
# Check current gas price
cast gas-price --rpc-url $RPC_URL

# Set max gas price limit (add to .env)
MAX_GAS_PRICE_GWEI=100
```

## API Integration

### Adding New Price Sources

1. Add source to `price-aggregator.ts`:

```typescript
async fetchNewIndexPrice(): Promise<number> {
  const response = await axios.get(`${API_URL}/index`);
  const price = parseFloat(response.data.price);
  return Math.round(price * 100);
}
```

2. Add to `fetchAllPrices()`:

```typescript
prices['new-index'] = await this.fetchNewIndexPrice();
```

3. Update `ORACLE_ADDRESSES` config with new source

## Contributing

When adding features:
1. Update TypeScript types
2. Add error handling
3. Update logs
4. Test with mock data first
5. Document changes

## Support

- GitHub Issues: [link]
- Discord: [link]
- Email: support@cs2index.com

## License

MIT
