import axios from 'axios';
import { logger } from './utils/logger';

/**
 * Price source interfaces
 */
interface PriceData {
  [key: string]: number; // key is the source identifier, value is priceX100
}

/**
 * PriceAggregator fetches CS2 index prices from external sources
 */
export class PriceAggregator {
  private readonly SKINFLOW_API = 'https://skinflow.gg/api';
  private readonly ESPORTFIRE_API = 'https://esportfire.com/api';
  private readonly BUFF163_API = 'https://buff.163.com/api';

  /**
   * Fetch all CS2 index prices
   */
  async fetchAllPrices(): Promise<PriceData> {
    const prices: PriceData = {};

    try {
      // Fetch Global Index price
      prices['global-index'] = await this.fetchGlobalIndexPrice();
    } catch (error: any) {
      logger.error(`Failed to fetch global index: ${error.message}`);
    }

    try {
      // Fetch Knives Index price
      prices['knives-index'] = await this.fetchKnivesIndexPrice();
    } catch (error: any) {
      logger.error(`Failed to fetch knives index: ${error.message}`);
    }

    try {
      // Fetch Rifles Index price
      prices['rifles-index'] = await this.fetchRiflesIndexPrice();
    } catch (error: any) {
      logger.error(`Failed to fetch rifles index: ${error.message}`);
    }

    try {
      // Fetch Gloves Index price
      prices['gloves-index'] = await this.fetchGlovesIndexPrice();
    } catch (error: any) {
      logger.error(`Failed to fetch gloves index: ${error.message}`);
    }

    return prices;
  }

  /**
   * Fetch CS2 Global Index price
   * Source: Buff163 or SkinFlow
   */
  private async fetchGlobalIndexPrice(): Promise<number> {
    try {
      // Try primary source: SkinFlow
      const response = await axios.get(`${this.SKINFLOW_API}/indexes/global`, {
        timeout: 5000,
        headers: {
          'User-Agent': 'CS2InDEX-Oracle/1.0',
        },
      });

      if (response.data && response.data.price) {
        const price = parseFloat(response.data.price);
        const priceX100 = Math.round(price * 100);
        logger.debug(`📊 Global Index (SkinFlow): $${price.toLocaleString()}`);
        return priceX100;
      }
    } catch (error: any) {
      logger.warn(`SkinFlow API error: ${error.message}`);
    }

    // Fallback: use mock data for development
    return this.getMockPrice('global-index');
  }

  /**
   * Fetch CS2 Knives Index price
   */
  private async fetchKnivesIndexPrice(): Promise<number> {
    try {
      const response = await axios.get(`${this.SKINFLOW_API}/indexes/knives`, {
        timeout: 5000,
        headers: {
          'User-Agent': 'CS2InDEX-Oracle/1.0',
        },
      });

      if (response.data && response.data.price) {
        const price = parseFloat(response.data.price);
        const priceX100 = Math.round(price * 100);
        logger.debug(`🔪 Knives Index (SkinFlow): $${price.toLocaleString()}`);
        return priceX100;
      }
    } catch (error: any) {
      logger.warn(`SkinFlow Knives API error: ${error.message}`);
    }

    return this.getMockPrice('knives-index');
  }

  /**
   * Fetch CS2 Rifles Index price
   */
  private async fetchRiflesIndexPrice(): Promise<number> {
    try {
      const response = await axios.get(`${this.ESPORTFIRE_API}/indexes/rifles`, {
        timeout: 5000,
        headers: {
          'User-Agent': 'CS2InDEX-Oracle/1.0',
        },
      });

      if (response.data && response.data.value) {
        const price = parseFloat(response.data.value);
        const priceX100 = Math.round(price * 100);
        logger.debug(`🔫 Rifles Index (EsportFire): $${price.toLocaleString()}`);
        return priceX100;
      }
    } catch (error: any) {
      logger.warn(`EsportFire Rifles API error: ${error.message}`);
    }

    return this.getMockPrice('rifles-index');
  }

  /**
   * Fetch CS2 Gloves Index price
   */
  private async fetchGlovesIndexPrice(): Promise<number> {
    try {
      const response = await axios.get(`${this.ESPORTFIRE_API}/indexes/gloves`, {
        timeout: 5000,
        headers: {
          'User-Agent': 'CS2InDEX-Oracle/1.0',
        },
      });

      if (response.data && response.data.value) {
        const price = parseFloat(response.data.value);
        const priceX100 = Math.round(price * 100);
        logger.debug(`🧤 Gloves Index (EsportFire): $${price.toLocaleString()}`);
        return priceX100;
      }
    } catch (error: any) {
      logger.warn(`EsportFire Gloves API error: ${error.message}`);
    }

    return this.getMockPrice('gloves-index');
  }

  /**
   * Get mock price for development/testing
   * Simulates realistic price movements
   */
  private getMockPrice(source: string): number {
    const basePrices: { [key: string]: number } = {
      'global-index': 400000000, // $4,000,000
      'knives-index': 70900000,  // $709,000
      'rifles-index': 15000000,  // $150,000
      'gloves-index': 25000000,  // $250,000
    };

    const basePrice = basePrices[source] || 100000;

    // Add random variation (-2% to +2%)
    const variation = (Math.random() - 0.5) * 0.04; // -0.02 to +0.02
    const price = Math.round(basePrice * (1 + variation));

    logger.debug(`🎲 Mock price for ${source}: $${(price / 100).toLocaleString()}`);
    return price;
  }

  /**
   * Fetch price for specific CS2 item
   * For individual item pools (AK47-Redline, AWP-Dragon Lore, etc.)
   */
  async fetchItemPrice(itemName: string): Promise<number> {
    try {
      // Normalize item name for API
      const normalizedName = itemName.replace(/\s+/g, '-').toLowerCase();

      const response = await axios.get(`${this.SKINFLOW_API}/items/${normalizedName}`, {
        timeout: 5000,
        headers: {
          'User-Agent': 'CS2InDEX-Oracle/1.0',
        },
      });

      if (response.data && response.data.price) {
        const price = parseFloat(response.data.price);
        const priceX100 = Math.round(price * 100);
        logger.debug(`💰 ${itemName}: $${price.toFixed(2)}`);
        return priceX100;
      }
    } catch (error: any) {
      logger.warn(`Failed to fetch ${itemName}: ${error.message}`);
    }

    // Fallback to mock prices
    const mockItemPrices: { [key: string]: number } = {
      'ak47-redline': 5000,        // $50
      'awp-dragon-lore': 250000,   // $2,500
      'm4a4-howl': 400000,         // $4,000
      'karambit-fade': 180000,     // $1,800
    };

    const normalizedName = itemName.toLowerCase().replace(/\s+/g, '-');
    const basePrice = mockItemPrices[normalizedName] || 10000;

    // Add variation
    const variation = (Math.random() - 0.5) * 0.04;
    return Math.round(basePrice * (1 + variation));
  }
}
