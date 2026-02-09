'use client';

/**
 * @fileoverview 持仓列表组件 (Positions List)
 * 获取并展示当前用户的所有持仓 (NFTs)。
 * 遵循 Google TypeScript Style Guide。
 *
 * @author Senior Architect
 */

import { useAccount, useReadContract } from 'wagmi';
import { POSITION_NFT_ABI } from '@/config/contracts';
import { PositionCard } from './PositionCard';
import { Layers } from 'lucide-react';

import { useLanguage } from '@/contexts/LanguageContext';

const POSITION_NFT_ADDRESS = '0x...' as `0x${string}`;

/**
 * 持仓列表主组件
 */
export function PositionsList() {
  const { address } = useAccount();
  const { t } = useLanguage();

  // 获取用户持仓数据
  // 返回值: [tokenIds[], positionData[]]
  const { data: positionsData, isLoading } = useReadContract({
    address: POSITION_NFT_ADDRESS,
    abi: POSITION_NFT_ABI,
    functionName: 'getPositionsByOwner',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
      refetchInterval: 10000, // 每 10 秒刷新一次
    },
  });

  const tokenIds = positionsData?.[0] || [];
  const positions = positionsData?.[1] || [];

  if (!address) {
    return null;
  }

  return (
    <div className="glass-card rounded-2xl p-6 mt-8">
      <div className="flex items-center gap-2 mb-6">
        <Layers className="text-accent-purple" size={24} />
        <h2 className="text-2xl font-bold text-white">
          {t.positions.title}
        </h2>
        {positions.length > 0 && (
          <span className="px-2 py-1 rounded-full bg-gray-700 text-xs text-gray-300">
            {positions.length}
          </span>
        )}
      </div>

      {isLoading ? (
        <div className="py-12 flex justify-center">
          <span className="loading loading-dots loading-lg text-primary-500"></span>
        </div>
      ) : positions.length === 0 ? (
        <div className="text-center py-16 border-2 border-dashed border-gray-700 rounded-xl bg-gray-800/30">
          <div className="bg-gray-800 w-16 h-16 rounded-full flex items-center justify-center mx-auto mb-4">
            <Layers className="text-gray-600" size={32} />
          </div>
          <p className="text-lg font-medium text-gray-300 mb-2">{t.positions.noPositions}</p>
          <p className="text-sm text-gray-500 max-w-sm mx-auto">
            {t.positions.noPositionsDesc}
          </p>
        </div>
      ) : (
        <div className="space-y-4">
          {positions.map((position, index) => (
            <PositionCard
              key={tokenIds[index].toString()}
              tokenId={tokenIds[index]}
              position={position}
            />
          ))}
        </div>
      )}
    </div>
  );
}

