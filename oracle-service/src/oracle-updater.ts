import { ethers } from 'ethers';
import { logger } from './utils/logger';

/**
 * Factory ABI — only the functions we need
 * updatePrice is guarded by onlyOwner; the caller must be the deployer wallet.
 */
const FACTORY_ABI = [
  'function updatePrice(address pool, uint256 newPrice) external',
  'function owner() external view returns (address)',
];

/**
 * Oracle ABI — read-only helpers (oraclePrice / updateTime are public mappings)
 */
const ORACLE_ABI = [
  'function oraclePrice(address pool) external view returns (uint256)',
  'function updateTime(address pool) external view returns (uint256)',
];

/**
 * OracleUpdater sends on-chain price updates via Factory.updatePrice().
 *
 * Authorization model:
 *   Factory.updatePrice() is onlyOwner — the wallet must be the Factory owner
 *   (i.e. the same key used during deployment).
 */
export class OracleUpdater {
  private provider: ethers.JsonRpcProvider;
  private wallet: ethers.Wallet;
  private factory: ethers.Contract;
  private oracle: ethers.Contract;

  constructor(rpcUrl: string, privateKey: string, factoryAddress: string, oracleAddress: string) {
    this.provider = new ethers.JsonRpcProvider(rpcUrl);
    this.wallet   = new ethers.Wallet(privateKey, this.provider);
    this.factory  = new ethers.Contract(factoryAddress, FACTORY_ABI, this.wallet);
    this.oracle   = new ethers.Contract(oracleAddress,  ORACLE_ABI,  this.provider);
    logger.info(`Price feeder wallet: ${this.wallet.address}`);
    logger.info(`Factory:             ${factoryAddress}`);
    logger.info(`Oracle:              ${oracleAddress}`);
  }

  /**
   * Verify the wallet is the Factory owner (called once at startup).
   */
  async verifyOwnership(): Promise<void> {
    const owner = await this.factory.owner();
    if (owner.toLowerCase() !== this.wallet.address.toLowerCase()) {
      throw new Error(
        `Wallet ${this.wallet.address} is not Factory owner. Owner is ${owner}`,
      );
    }
    logger.info('Ownership verified: wallet is Factory owner');
  }

  /**
   * Update the oracle price for a specific pool via Factory.
   *
   * @param poolAddress  - The Pool contract address (first arg to Factory.updatePrice)
   * @param priceX100    - New price × 100 (e.g. 50000 = $500.00)
   * @returns Transaction hash
   */
  async updatePool(poolAddress: string, priceX100: number): Promise<string> {
    // Read current on-chain price from Oracle mapping
    const currentPrice = await this.oracle.oraclePrice(poolAddress);
    const currentNum   = Number(currentPrice);

    // Skip if price change is too small (< 0.1%)
    if (currentNum > 0) {
      const priceDiffPercent = Math.abs(currentNum - priceX100) / currentNum * 100;
      if (priceDiffPercent < 0.1) {
        logger.debug(`Price change ${priceDiffPercent.toFixed(4)}% < 0.1%, skipping`);
        throw new Error('Price change below threshold');
      }
    }

    // Skip if last update was too recent (< 60 s)
    const lastUpdate    = await this.oracle.updateTime(poolAddress);
    const timeSinceUpdate = Date.now() / 1000 - Number(lastUpdate);
    if (timeSinceUpdate < 60) {
      logger.debug(`Last update ${timeSinceUpdate.toFixed(0)}s ago, waiting…`);
      throw new Error('Update interval too short');
    }

    logger.debug(`Sending updatePrice(${poolAddress}, ${priceX100})`);

    // Call Factory.updatePrice → oracle.updateIndexPrice → pool.updateOraclePrice
    const tx = await this.factory.updatePrice(poolAddress, priceX100, {
      gasLimit: 150_000,
    });

    logger.debug(`Waiting for confirmation: ${tx.hash}`);
    await tx.wait();

    return tx.hash as string;
  }

  /** Read the current on-chain oracle price for a pool (for diagnostics). */
  async getCurrentPrice(poolAddress: string): Promise<number> {
    const price = await this.oracle.oraclePrice(poolAddress);
    return Number(price);
  }

  /** Read the last update timestamp for a pool. */
  async getLastUpdateTime(poolAddress: string): Promise<number> {
    const ts = await this.oracle.updateTime(poolAddress);
    return Number(ts);
  }
}
