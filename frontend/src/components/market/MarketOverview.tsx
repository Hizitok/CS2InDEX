'use client';

import { useReadContract } from 'wagmi';
import { formatUnits } from 'viem';
import { POOL_ABI } from '@/config/contracts';
import { TrendingUp } from 'lucide-react';

const POOLS = [
  { name: 'AK47-Redline', address: '0x...' as `0x${string}` },
  { name: 'AWP-Dragon Lore', address: '0x...' as `0x${string}` },
  { name: 'M4A4-Howl', address: '0x...' as `0x${string}` },
];

function MarketCard({ name, address }: { name: string; address: `0x${string}` }) {
  const { data: poolInfo } = useReadContract({
    address,
    abi: POOL_ABI,
    functionName: 'getPoolInfo',
    query: { refetchInterval: 10000 },
  });

  const lastPrice = poolInfo?.[0] ? Number(poolInfo[0]) / 100 : 0;
  const oraclePrice = poolInfo?.[1] ? Number(poolInfo[1]) / 100 : 0;
  const askMin = poolInfo?.[3] ? Number(poolInfo[3]) / 100 : 0;
  const bidMax = poolInfo?.[4] ? Number(poolInfo[4]) / 100 : 0;

  const spread = askMin && bidMax ? ((askMin - bidMax) / bidMax * 100).toFixed(2) : '0';

  return (
    <div className="bg-gray-700/50 rounded-lg p-4 hover:bg-gray-700/70 transition-colors cursor-pointer">
      <div className="flex items-center justify-between mb-3">
        <div>
          <h3 className="font-semibold">{name}</h3>
          <div className="text-sm text-gray-400">Perpetual</div>
        </div>
        <TrendingUp className="text-primary-500" size={20} />
      </div>

      <div className="space-y-2">
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Last Price</span>
          <span className="font-semibold">${lastPrice.toFixed(2)}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Oracle</span>
          <span className="font-semibold">${oraclePrice.toFixed(2)}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Best Bid/Ask</span>
          <span className="font-semibold">
            ${bidMax.toFixed(2)} / ${askMin > 0 ? askMin.toFixed(2) : '-'}
          </span>
        </div>
        {bidMax > 0 && askMin > 0 && (
          <div className="flex justify-between text-sm">
            <span className="text-gray-400">Spread</span>
            <span className="text-orange-500">{spread}%</span>
          </div>
        )}
      </div>
    </div>
  );
}

export function MarketOverview() {
  return (
    <div className="card">
      <h2 className="text-2xl font-bold mb-6">Markets</h2>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {POOLS.map(pool => (
          <MarketCard key={pool.name} name={pool.name} address={pool.address} />
        ))}
      </div>
    </div>
  );
}
