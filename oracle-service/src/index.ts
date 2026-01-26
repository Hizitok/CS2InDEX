import dotenv from 'dotenv';
import cron from 'node-cron';
import { OracleUpdater } from './oracle-updater';
import { PriceAggregator } from './price-aggregator';
import { logger } from './utils/logger';

dotenv.config();

/**
 * Main entry point for CS2InDEX Oracle Service
 * Fetches CS2 index prices from external sources and updates on-chain oracles
 */
async function main() {
  logger.info('🚀 Starting CS2InDEX Oracle Service...');

  // Validate environment variables
  const requiredEnvVars = [
    'RPC_URL',
    'PRICE_FEEDER_PRIVATE_KEY',
    'ORACLE_ADDRESSES',
  ];

  for (const envVar of requiredEnvVars) {
    if (!process.env[envVar]) {
      logger.error(`❌ Missing required environment variable: ${envVar}`);
      process.exit(1);
    }
  }

  // Initialize services
  const priceAggregator = new PriceAggregator();
  const oracleUpdater = new OracleUpdater(
    process.env.RPC_URL!,
    process.env.PRICE_FEEDER_PRIVATE_KEY!
  );

  // Parse oracle addresses from environment
  const oracleConfigs = JSON.parse(process.env.ORACLE_ADDRESSES!);
  logger.info(`📊 Configured ${oracleConfigs.length} oracle(s)`);

  /**
   * Update all oracle prices
   */
  async function updatePrices() {
    logger.info('📈 Starting price update cycle...');

    try {
      // Fetch latest prices from all sources
      const prices = await priceAggregator.fetchAllPrices();

      // Update each oracle
      for (const config of oracleConfigs) {
        const { name, address, source } = config;

        if (!prices[source]) {
          logger.warn(`⚠️  No price data for ${name} (source: ${source})`);
          continue;
        }

        const priceX100 = prices[source];

        try {
          const tx = await oracleUpdater.updateOracle(address, priceX100);
          logger.info(`✅ Updated ${name}: $${(priceX100 / 100).toLocaleString()} (tx: ${tx})`);
        } catch (error: any) {
          logger.error(`❌ Failed to update ${name}: ${error.message}`);
        }
      }

      logger.info('✨ Price update cycle completed');
    } catch (error: any) {
      logger.error(`❌ Error in price update cycle: ${error.message}`);
    }
  }

  // Run initial update
  await updatePrices();

  // Schedule updates every 5 minutes
  const updateInterval = process.env.UPDATE_INTERVAL_MINUTES || '5';
  cron.schedule(`*/${updateInterval} * * * *`, async () => {
    await updatePrices();
  });

  logger.info(`⏰ Scheduled price updates every ${updateInterval} minutes`);
  logger.info('✅ Oracle service is running...');
}

// Handle graceful shutdown
process.on('SIGINT', () => {
  logger.info('🛑 Shutting down oracle service...');
  process.exit(0);
});

process.on('SIGTERM', () => {
  logger.info('🛑 Shutting down oracle service...');
  process.exit(0);
});

// Start the service
main().catch((error) => {
  logger.error('💥 Fatal error:', error);
  process.exit(1);
});
