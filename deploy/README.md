# CS2InDEX Deployment Guide

Complete guide for deploying the CS2InDEX protocol to testnets and mainnet.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- RPC URLs for target networks (Alchemy/Infura)
- Deployer wallet with sufficient ETH for gas
- Etherscan API key for contract verification

## Environment Setup

1. **Copy environment template:**
   ```bash
   cp .env.example .env
   ```

2. **Configure environment variables:**
   ```bash
   # RPC URLs
   MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR-API-KEY
   SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR-API-KEY

   # API Keys
   ETHERSCAN_API_KEY=YOUR-ETHERSCAN-API-KEY

   # Deployment Configuration
   PRIVATE_KEY=0x...                    # Deployer private key
   DEPLOYER_ADDRESS=0x...               # Deployer address
   INSURANCE_FUND=0x...                 # Insurance fund address (multisig recommended)
   PRICE_FEEDER=0x...                   # Price feeder address (for oracle updates)
   ```

## Network-Specific Deployment

### Sepolia Testnet Deployment

Deploy to Sepolia for testing:

```bash
# Deploy entire protocol with mock USDC
forge script script/Deploy.s.sol \
  --rpc-url sepolia \
  --broadcast \
  --verify \
  -vvvv
```

This will deploy:
- MockERC20 (USDC with 6 decimals)
- Vault contract
- Liquidation Engine
- ADL Engine
- Factory
- Multiple trading pools for CS2 indices

**Deployed Pools:**
1. CS2-Global-Index
2. CS2-Knives-Index
3. AK47-Redline
4. AWP-Dragon-Lore
5. M4A4-Howl
6. Karambit-Fade

### Mainnet Deployment

**CRITICAL**: Review all configurations before mainnet deployment!

```bash
# Deploy to mainnet (uses real USDC at 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
forge script script/DeployMainnet.s.sol \
  --rpc-url mainnet \
  --broadcast \
  --verify \
  --slow \
  -vvvv
```

**Mainnet Pools:**
1. CS2-Global-Index ($4M initial price)
2. CS2-Knives-Index ($709K initial price)
3. CS2-Rifles-Index ($150K initial price)
4. CS2-Gloves-Index ($250K initial price)

## Post-Deployment Steps

### 1. Verify Contracts on Etherscan

If automatic verification fails, manually verify:

```bash
# Verify Vault
forge verify-contract \
  <VAULT_ADDRESS> \
  src/Vault.sol:Vault \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(address)" <USDC_ADDRESS>)

# Verify Factory
forge verify-contract \
  <FACTORY_ADDRESS> \
  src/Factory.sol:CS2InDEXFactory \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(address,address)" <VAULT_ADDRESS> <INSURANCE_FUND>)

# Verify each Pool
forge verify-contract \
  <POOL_ADDRESS> \
  src/Pool.sol:Pool \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address,uint256,uint256)" <VAULT> <NFT> <CURRENCY> <ORACLE> <DECIMAL> <PRICE>)
```

### 2. Update Frontend Configuration

Edit `frontend/src/config/contracts.ts`:

```typescript
export const CONTRACTS = {
  VAULT: '0x...' as `0x${string}`,        // From deployment output
  FACTORY: '0x...' as `0x${string}`,      // From deployment output
  USDC: '0x...' as `0x${string}`,         // USDC address
};

export const POOLS = {
  'CS2-Global-Index': {
    pool: '0x...',
    oracle: '0x...',
    nft: '0x...',
  },
  'CS2-Knives-Index': {
    pool: '0x...',
    oracle: '0x...',
    nft: '0x...',
  },
  // Add other pools...
};
```

### 3. Set Up Oracle Price Feed Service

The oracle needs regular price updates. Create a backend service:

```typescript
// Example: price-feed-service/index.ts
import { ethers } from 'ethers';

async function updateOraclePrices() {
  // Fetch prices from skinflow.gg or esportfire.com
  const globalIndexPrice = await fetchGlobalIndexPrice();
  const knivesIndexPrice = await fetchKnivesIndexPrice();

  // Update oracle contracts
  const oracle = new ethers.Contract(ORACLE_ADDRESS, ORACLE_ABI, signer);
  await oracle.updatePrice(globalIndexPrice);
}

// Run every 5 minutes
setInterval(updateOraclePrices, 5 * 60 * 1000);
```

### 4. Fund Insurance Fund

Transfer USDC to the insurance fund:

```bash
# Calculate recommended amount (10% of expected TVL)
# Example: If expecting $1M TVL, fund with 100K USDC

# Transfer USDC to insurance fund
cast send <USDC_ADDRESS> \
  "transfer(address,uint256)" \
  <INSURANCE_FUND> \
  100000000000 \  # 100K USDC (6 decimals)
  --rpc-url mainnet \
  --private-key $PRIVATE_KEY
```

### 5. Transfer Ownership (Mainnet Only)

**CRITICAL**: Transfer ownership to multisig for security:

```bash
# Transfer Factory ownership
cast send <FACTORY_ADDRESS> \
  "transferOwnership(address)" \
  <MULTISIG_ADDRESS> \
  --rpc-url mainnet \
  --private-key $PRIVATE_KEY

# Transfer LiquidationEngine ownership
cast send <LIQUIDATION_ENGINE> \
  "transferOwnership(address)" \
  <MULTISIG_ADDRESS> \
  --rpc-url mainnet \
  --private-key $PRIVATE_KEY

# Transfer ADLEngine ownership
cast send <ADL_ENGINE> \
  "transferOwnership(address)" \
  <MULTISIG_ADDRESS> \
  --rpc-url mainnet \
  --private-key $PRIVATE_KEY
```

### 6. Initial Liquidity (Optional)

To bootstrap trading, provide initial liquidity:

```bash
# Approve USDC
cast send <USDC_ADDRESS> \
  "approve(address,uint256)" \
  <VAULT_ADDRESS> \
  1000000000000 \  # 1M USDC
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY

# Deposit to vault
cast send <VAULT_ADDRESS> \
  "deposit(uint256)" \
  1000000000000 \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY
```

## Testing Deployment

After deployment, test critical functions:

```bash
# 1. Test deposit
cast send <VAULT_ADDRESS> "deposit(uint256)" 1000000 --rpc-url sepolia --private-key $PRIVATE_KEY

# 2. Check balance
cast call <VAULT_ADDRESS> "balanceOf(address)(uint256)" <YOUR_ADDRESS> --rpc-url sepolia

# 3. Test order creation (requires encoding PoolOrder struct)
# Use frontend for easier testing

# 4. Check pool info
cast call <FACTORY_ADDRESS> "getPoolInfo(string)(tuple)" "CS2-Global-Index" --rpc-url sepolia
```

## Deployment Checklist

### Pre-Deployment
- [ ] Environment variables configured
- [ ] Sufficient ETH for gas in deployer wallet
- [ ] Insurance fund address configured (multisig recommended)
- [ ] Price feeder address configured
- [ ] Reviewed pool configurations and initial prices
- [ ] Tested on local fork: `forge test`

### During Deployment
- [ ] Deploy script executed successfully
- [ ] All contract addresses recorded
- [ ] Deployment transactions confirmed
- [ ] No errors in deployment logs

### Post-Deployment
- [ ] All contracts verified on Etherscan
- [ ] Frontend configuration updated with addresses
- [ ] Oracle price feed service deployed and running
- [ ] Insurance fund funded with USDC
- [ ] Ownership transferred to multisig (mainnet only)
- [ ] Initial liquidity provided (if needed)
- [ ] All critical functions tested
- [ ] Monitoring and alerts configured

## Monitoring

Set up monitoring for:
- Oracle price staleness
- Insurance fund balance
- Liquidation events
- TVL and trading volume
- Gas costs for operations

## Emergency Procedures

### Pause Protocol

If critical bug discovered:

```bash
# Pause trading on specific pool
cast send <FACTORY_ADDRESS> \
  "togglePoolStatus(string)" \
  "CS2-Global-Index" \
  --rpc-url mainnet \
  --private-key $MULTISIG_KEY
```

### Update Oracle in Emergency

```bash
# Update price manually
cast send <ORACLE_ADDRESS> \
  "updatePrice(uint256)" \
  <NEW_PRICE_X100> \
  --rpc-url mainnet \
  --private-key $PRICE_FEEDER_KEY
```

## Upgrade Path

This version uses immutable contracts. For upgrades:
1. Deploy new version of contracts
2. Migrate liquidity to new version
3. Update frontend to point to new contracts
4. Archive old contracts (read-only)

## Gas Optimization

Expected gas costs:
- Vault deposit: ~50K gas
- Order creation: ~200K gas
- Order matching: ~300K gas
- Position close: ~250K gas
- Liquidation: ~150K gas

## Support

For deployment issues:
- Review deployment logs in `broadcast/` folder
- Check Foundry book: https://book.getfoundry.sh
- Open GitHub issue
- Contact team on Discord

## Additional Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [Etherscan Verification](https://docs.etherscan.io/tutorials/verifying-contracts-programmatically)
- [Alchemy RPC](https://www.alchemy.com/)
- [CS2 Price Indices](https://skinflow.gg/csgo-stash/graph/overview)
