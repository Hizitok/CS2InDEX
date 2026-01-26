import { ethers } from 'ethers';
import { logger } from './utils/logger';

/**
 * Oracle ABI - minimal interface for updatePrice function
 */
const ORACLE_ABI = [
  'function updatePrice(uint256 newPriceX100) external',
  'function latestPriceX100() external view returns (uint256)',
  'function lastUpdateTime() external view returns (uint256)',
  'function priceFeeder() external view returns (address)',
];

/**
 * OracleUpdater handles on-chain price updates
 */
export class OracleUpdater {
  private provider: ethers.JsonRpcProvider;
  private wallet: ethers.Wallet;

  constructor(rpcUrl: string, privateKey: string) {
    this.provider = new ethers.JsonRpcProvider(rpcUrl);
    this.wallet = new ethers.Wallet(privateKey, this.provider);
    logger.info(`🔑 Price feeder address: ${this.wallet.address}`);
  }

  /**
   * Update oracle price on-chain
   * @param oracleAddress - Address of the oracle contract
   * @param priceX100 - New price multiplied by 100
   * @returns Transaction hash
   */
  async updateOracle(oracleAddress: string, priceX100: number): Promise<string> {
    const oracle = new ethers.Contract(oracleAddress, ORACLE_ABI, this.wallet);

    // Check if price has changed significantly (> 0.1%)
    const currentPrice = await oracle.latestPriceX100();
    const priceDiff = Math.abs(Number(currentPrice) - priceX100);
    const priceDiffPercent = (priceDiff / Number(currentPrice)) * 100;

    if (priceDiffPercent < 0.1) {
      logger.debug(`⏭️  Price change too small (${priceDiffPercent.toFixed(4)}%), skipping update`);
      throw new Error('Price change below threshold');
    }

    // Check if enough time has passed since last update (minimum 1 minute)
    const lastUpdate = await oracle.lastUpdateTime();
    const timeSinceUpdate = Date.now() / 1000 - Number(lastUpdate);

    if (timeSinceUpdate < 60) {
      logger.debug(`⏳ Last update was ${timeSinceUpdate.toFixed(0)}s ago, waiting...`);
      throw new Error('Update interval too short');
    }

    // Verify we are the authorized price feeder
    const authorizedFeeder = await oracle.priceFeeder();
    if (authorizedFeeder.toLowerCase() !== this.wallet.address.toLowerCase()) {
      throw new Error(`Not authorized price feeder. Expected: ${authorizedFeeder}, Got: ${this.wallet.address}`);
    }

    // Send update transaction
    logger.debug(`📤 Sending price update: ${priceX100} (${(priceX100 / 100).toLocaleString()})`);

    const tx = await oracle.updatePrice(priceX100, {
      gasLimit: 100000, // Conservative gas limit
    });

    logger.debug(`⏳ Waiting for confirmation: ${tx.hash}`);
    await tx.wait();

    return tx.hash;
  }

  /**
   * Get current oracle price
   */
  async getCurrentPrice(oracleAddress: string): Promise<number> {
    const oracle = new ethers.Contract(oracleAddress, ORACLE_ABI, this.provider);
    const price = await oracle.latestPriceX100();
    return Number(price);
  }

  /**
   * Get last update time
   */
  async getLastUpdateTime(oracleAddress: string): Promise<number> {
    const oracle = new ethers.Contract(oracleAddress, ORACLE_ABI, this.provider);
    const timestamp = await oracle.lastUpdateTime();
    return Number(timestamp);
  }
}
