'use client';

/**
 * @fileoverview 持仓列表组件 (Positions List)
 * 获取并展示当前用户的所有持仓 (NFTs)。
 * 遵循 Google TypeScript Style Guide。
 *
 * @author Senior Architect
 */

import { useState, useEffect } from 'react';
import { useAccount, useReadContract } from 'wagmi';
import { ROUTER_ABI, CONTRACTS } from '@/config/contracts';
import { PositionCard } from './PositionCard';
import { Layers, EyeOff, Eye } from 'lucide-react';

import { useLanguage } from '@/contexts/LanguageContext';

const HIDE_SETTLED_KEY = 'cs2index:hideSettled';

/**
 * 持仓列表主组件
 */
export function PositionsList() {
  const { address } = useAccount();
  const { t } = useLanguage();

  // Persist "hide settled" preference in localStorage
  const [hideSettled, setHideSettled] = useState<boolean>(false);
  useEffect(() => {
    setHideSettled(localStorage.getItem(HIDE_SETTLED_KEY) === 'true');
  }, []);
  const toggleHideSettled = () => {
    setHideSettled(prev => {
      const next = !prev;
      localStorage.setItem(HIDE_SETTLED_KEY, String(next));
      return next;
    });
  };

  // 通过 Router.getPortfolio 获取持仓（包含 pool 地址）
  const { data: portfolio, isLoading } = useReadContract({
    address: CONTRACTS.ROUTER,
    abi: ROUTER_ABI,
    functionName: 'getPortfolio',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
      refetchInterval: 10000, // 每 10 秒刷新一次
    },
  });

  // 将 PositionView[] 转换为 PositionCard 期望的格式（pool 地址现在正确填充）
  const positions = (portfolio ?? []).map((view) => ({
    positionID:      view.posId,
    pool:            view.pool as string,
    isShort:         view.pos.isShort,
    status:          Number(view.pos.status),
    openMargin:      view.pos.openMargin,
    pendingSize:     view.pos.pendingSize,
    openSize:        view.pos.openSize,
    closeSize:       view.pos.closeSize,
    openAmount:      view.pos.openAmount,
    closeAmount:     view.pos.closeAmount,
    openFundingIdx:  view.pos.openFundingIdx,
    closeFundingIdx: view.pos.closeFundingIdx,
  }));

  // Sort: settled (status=6) always last, others preserve original order
  const sorted = [...positions].sort((a, b) => {
    const aS = a.status === 6 ? 1 : 0;
    const bS = b.status === 6 ? 1 : 0;
    return aS - bS;
  });

  const displayed = hideSettled ? sorted.filter(p => p.status !== 6) : sorted;
  const settledCount = positions.filter(p => p.status === 6).length;

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
            {displayed.length}
          </span>
        )}
        {settledCount > 0 && (
          <button
            onClick={toggleHideSettled}
            className={`ml-auto flex items-center gap-1.5 px-3 py-1.5 rounded-lg border text-xs font-medium transition-all ${
              hideSettled
                ? 'border-gray-600 text-gray-400 hover:border-gray-500 hover:text-gray-300'
                : 'border-white/10 text-gray-500 hover:border-white/20 hover:text-gray-400'
            }`}
          >
            {hideSettled ? <Eye size={13} /> : <EyeOff size={13} />}
            {hideSettled
              ? `${t.positions.showSettled} (${settledCount})`
              : `${t.positions.hideSettled} (${settledCount})`}
          </button>
        )}
      </div>

      {isLoading ? (
        <div className="py-12 flex justify-center">
          <span className="loading loading-dots loading-lg text-primary-500"></span>
        </div>
      ) : displayed.length === 0 ? (
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
          {displayed.map((position) => (
            <PositionCard
              key={position.positionID.toString()}
              tokenId={position.positionID}
              position={position}
            />
          ))}
        </div>
      )}
    </div>
  );
}
