'use client';

/**
 * @fileoverview 市场概览组件 (Market Overview)
 * 展示各交易对的实时价格、预言机价格、买卖盘口及价差 (Spread)。
 * 遵循 Google TypeScript Style Guide。
 *
 * @author Senior Architect
 */

import { useReadContract } from 'wagmi';
import { formatUnits } from 'viem';
import { POOL_ABI, INDEX_ORACLE_ABI } from '@/config/contracts';
import { TrendingUp, Activity, AlertCircle, Clock } from 'lucide-react';
import { motion } from 'framer-motion';
import { useLanguage } from '@/contexts/LanguageContext';

// 市场配置
// Index Configuration
const INDEX_POOL = { name: 'CS2 Market Index', address: '0x...' as `0x${string}` };

/**
 * 单个市场卡片组件
 * @param {Object} props
 * @param {string} props.name - 资产名称
 * @param {string} props.address - Pool 合约地址
 */
function MarketCard({ name, address }: { name: string; address: `0x${string}` }) {
  const { t } = useLanguage();
  // 读取 Pool 信息 (价格等)
  const { data: poolInfo } = useReadContract({
    address,
    abi: POOL_ABI,
    functionName: 'getOrderbookInfo',
    query: { refetchInterval: 5000 },
  });

  const { data: oraclePriceData } = useReadContract({
    address,
    abi: POOL_ABI,
    functionName: 'oraclePrice',
    query: { refetchInterval: 5000 },
  });

  // 解析链上数据
  // 注意：假设价格精度为 2 (100 = 1.00 USD)，具体需根据合约定义调整 formatUnits 参数。
  // 为了安全展示，尽量避免 number 运算，使用 calculated string 或 bigint operation。

  // 临时使用 Number 进行展示转换 (假设值域在安全整数范围内)
  // 生产环境建议使用 bignumber.js 处理
  // 4. Get Oracle Address from Pool
  const { data: oracleAddress } = useReadContract({
    address: address,
    abi: POOL_ABI,
    functionName: 'oracle',
  });

  // 5. Get Real-time Funding Rate from Oracle
  const { data: fundingData } = useReadContract({
    address: oracleAddress, // Dynamic address
    abi: INDEX_ORACLE_ABI,
    functionName: 'calculateFundingRate',
    args: [address],
    query: {
      enabled: !!oracleAddress,
      refetchInterval: 10000
    }
  });

  const lastPriceBigInt = poolInfo?.[0]; // lastPrice
  const oraclePriceBigInt = oraclePriceData; // from oraclePrice()
  const askMinBigInt = poolInfo?.[1]; // ask1Price (Sell)
  const bidMaxBigInt = poolInfo?.[2]; // bid1Price (Buy)

  const lastPrice = lastPriceBigInt ? parseFloat(formatUnits(lastPriceBigInt, 18)) : 0;
  const oraclePrice = oraclePriceBigInt ? parseFloat(formatUnits(oraclePriceBigInt, 18)) : 0;

  // Funding Rate is in basis points (1 bp = 0.01%)
  // fundingData = [rate, avgPremium, interest]
  const fundingRateBp = fundingData ? Number(fundingData[0]) : 0;
  const fundingRatePercent = fundingRateBp / 100; // e.g. 200 => 2.00%

  // Spread Calculation
  const askMin = askMinBigInt ? parseFloat(formatUnits(askMinBigInt, 18)) : 0;
  const bidMax = bidMaxBigInt ? parseFloat(formatUnits(bidMaxBigInt, 18)) : 0;
  const spread = (askMin > 0 && bidMax > 0)
    ? ((askMin - bidMax) / askMin * 100).toFixed(2)
    : '0.00';

  const isPositiveSpread = parseFloat(spread) >= 0;

  return (
    <motion.div
      whileHover={{ scale: 1.02, transition: { duration: 0.2 } }}
      whileTap={{ scale: 0.98 }}
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="bg-bedrock-900/50 border border-white/5 rounded-xl p-6"
    >
      <div className="flex items-center justify-between mb-6">
        <div>
          <h3 className="font-bold text-2xl text-white group-hover:text-accent-cyan transition-colors">
            {name}
          </h3>
          <div className="text-xs text-gray-500 flex items-center gap-1 mt-1">
            <Activity size={12} /> Perpetual Contract
          </div>
        </div>
        <div className="bg-gray-800 p-2 rounded-lg group-hover:bg-primary-900/30 transition-colors">
          <TrendingUp className="text-primary-500" size={20} />
        </div>
      </div>

      <div className="space-y-3">
        <div className="flex justify-between text-sm py-1 border-b border-gray-700/50">
          <span className="text-gray-400">{t.market.lastPrice}</span>
          <span className="font-mono font-semibold text-white">${lastPrice.toFixed(2)}</span>
        </div>

        <div className="flex justify-between text-sm py-1 border-b border-gray-700/50">
          <span className="text-gray-400">{t.market.oraclePrice}</span>
          <span className="font-mono font-semibold text-blue-300">${oraclePrice.toFixed(2)}</span>
        </div>

        <div className="flex justify-between text-sm py-1 border-b border-gray-700/50">
          <span className="text-gray-400">{t.market.high} / {t.market.low}</span>
          <span className="font-mono font-semibold text-gray-300">
            ${bidMax.toFixed(2)} / <span className="text-gray-200">${askMin > 0 ? askMin.toFixed(2) : '-'}</span>
          </span>
        </div>

        <div className="flex justify-between text-sm py-1 border-b border-white/5">
          <span className="text-gray-400 flex items-center gap-1">
            {t.market.funding}
            <Clock size={12} className="text-gray-500" />
          </span>
          <span className={`font-mono font-semibold ${fundingRatePercent >= 0 ? 'text-accent-cyan' : 'text-accent-purple'}`}>
            {fundingRatePercent.toFixed(4)}%
          </span>
        </div>

        <div className="flex justify-between text-sm py-1">
          <span className="text-gray-400 flex items-center gap-1">
            {t.market.spread}
            {parseFloat(spread) > 1 && <AlertCircle size={12} className="text-orange-500" />}
          </span>
          <span className={`font-mono font-semibold ${parseFloat(spread) > 1 ? 'text-orange-400' : 'text-green-400'
            }`}>
            {spread}%
          </span>
        </div>
      </div>
    </motion.div>
  );
}

/**
 * 市场概览主组件
 */
export function MarketOverview() {
  const { t } = useLanguage();

  return (
    <div className="glass-card rounded-2xl p-6 h-full flex flex-col">
      <h2 className="text-2xl font-bold mb-6 text-white flex items-center gap-2">
        <Activity className="text-accent-cyan" />
        <span className="text-neon">{t.market.title}</span>
      </h2>

      <div className="flex-1">
        <MarketCard name={INDEX_POOL.name} address={INDEX_POOL.address} />
      </div>
    </div>
  );
}

