import dotenv from 'dotenv';
import cron from 'node-cron';
import { OracleUpdater } from './oracle-updater';
import { PriceAggregator } from './price-aggregator';
import { logger } from './utils/logger';

dotenv.config();

/**
 * Main entry point for CS2InDEX Oracle Service
 *
 * Authorization: the PRIVATE_KEY must be the Factory owner (deployer key).
 * Price update path: this service → Factory.updatePrice(pool, price)
 *                    → IndexOracle.updateIndexPrice(pool, price)
 *                    → Pool.updateOraclePrice(price)
 */
async function main() {
  logger.info('Starting CS2InDEX Oracle Service...');

  // Validate required environment variables
  const requiredEnvVars = [
    'RPC_URL',
    'PRIVATE_KEY',
    'FACTORY_ADDRESS',
    'ORACLE_ADDRESS',
    'POOL_CONFIGS',
  ];

  for (const envVar of requiredEnvVars) {
    if (!process.env[envVar]) {
      logger.error(`Missing required environment variable: ${envVar}`);
      process.exit(1);
    }
  }

  // Initialize services
  const priceAggregator = new PriceAggregator();
  const oracleUpdater = new OracleUpdater(
    process.env.RPC_URL!,
    process.env.PRIVATE_KEY!,
    process.env.FACTORY_ADDRESS!,
    process.env.ORACLE_ADDRESS!,
  );

  // Verify the wallet is Factory owner before starting
  await oracleUpdater.verifyOwnership();

  // Parse pool configs from environment
  // Format: [{ "name": "CS2 Global Index", "pool": "0x...", "source": "global-index" }, ...]
  const poolConfigs: Array<{ name: string; pool: string; source: string }> =
    JSON.parse(process.env.POOL_CONFIGS!);
  logger.info(`Configured ${poolConfigs.length} pool(s)`);

  /**
   * Update all pool oracle prices
   */
  async function updatePrices() {
    logger.info('Starting price update cycle...');

    try {
      const prices = await priceAggregator.fetchAllPrices();

      for (const config of poolConfigs) {
        const { name, pool, source } = config;

        if (!prices[source]) {
          logger.warn(`No price data for ${name} (source: ${source})`);
          continue;
        }

        const priceX100 = prices[source];

        try {
          const tx = await oracleUpdater.updatePool(pool, priceX100);
          logger.info(`Updated ${name}: $${(priceX100 / 100).toLocaleString()} (tx: ${tx})`);
        } catch (error: any) {
          // Threshold / interval errors are debug-level, not errors
          if (
            error.message === 'Price change below threshold' ||
            error.message === 'Update interval too short'
          ) {
            logger.debug(`Skipped ${name}: ${error.message}`);
          } else {
            logger.error(`Failed to update ${name}: ${error.message}`);
          }
        }
      }

      logger.info('Price update cycle completed');
    } catch (error: any) {
      logger.error(`Error in price update cycle: ${error.message}`);
    }
  }

  // Run initial update immediately
  await updatePrices();

  // Schedule updates every N minutes
  const updateInterval = process.env.UPDATE_INTERVAL_MINUTES || '5';
  cron.schedule(`*/${updateInterval} * * * *`, async () => {
    await updatePrices();
  });

  logger.info(`Scheduled price updates every ${updateInterval} minutes`);
  logger.info('Oracle service is running...');
}

// Graceful shutdown
process.on('SIGINT',  () => { logger.info('Shutting down oracle service...'); process.exit(0); });
process.on('SIGTERM', () => { logger.info('Shutting down oracle service...'); process.exit(0); });

main().catch((error) => {
  logger.error('Fatal error:', error);
  process.exit(1);
});
