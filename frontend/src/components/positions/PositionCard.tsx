'use client';

/**
 * @fileoverview 持仓卡片组件 (Position Card)
 * 展示单个持仓的详细信息 (方向、盈亏、杠杆) 并提供平仓功能。
 * 遵循 Google TypeScript Style Guide。
 *
 * @author Senior Architect
 */

import { useState } from 'react';
import { formatUnits, parseUnits } from 'viem';
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { POOL_ABI, PX_DECIMALS, ORDER_TYPE } from '@/config/contracts';
import toast from 'react-hot-toast';
import { TrendingUp, TrendingDown, X, Info, ShieldAlert } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';

/**
 * 持仓数据结构
 * @interface Position
 */
interface Position {
  positionID: bigint;
  pool: string;
  isShort: boolean;
  status: number; // 0=none, 1=pendingOpen, 2=open, 3=pendingClose, 4=liquidating, 5=closed, 6=settled
  openMargin: bigint;
  pendingSize: bigint;
  openSize: bigint;
  closeSize: bigint;
  openAmount: bigint; // Total value at open (Size * Price)
  closeAmount: bigint;
  openFundingIdx: bigint;
  closeFundingIdx: bigint;
}

interface PositionCardProps {
  tokenId: bigint;
  position: Position;
}

const STATUS_NAMES = ['None', 'Pending Open', 'Open', 'Pending Close', 'Liquidating', 'Closed', 'Settled'];

/**
 * 单个持仓卡片
 */
export function PositionCard({ tokenId, position }: PositionCardProps) {
  // UI 状态
  const [showCloseModal, setShowCloseModal] = useState(false);
  const [closePrice, setClosePrice] = useState<string>('');
  const { t } = useLanguage();

  // 合约写入
  const { writeContract, data: hash, error: writeError } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash });

  // --- 数据计算 (Data Calculation) ---

  // 1. 计算平均开仓价格 (Entry Price)
  // Formula: OpenAmount / OpenSize / 100 (Price decimal = 2)
  // 注意：OpenSize 是单位数，OpenAmount 是总价值(Price*Size)
  // pxDecimals = 6: openAmount = sum(matchedPrice * matchedSize), both in 6 decimals
  // entryPrice = openAmount / openSize (result is in 6 decimals, divide by 1e6 for display)
  let entryPrice = 0;
  try {
    if (position.openSize > 0n) {
      const priceScaled = Number(position.openAmount) / Number(position.openSize);
      entryPrice = priceScaled / (10 ** PX_DECIMALS);
    }
  } catch (e) {
    console.error('Error calculating entry price', e);
  }

  // 2. 格式化保证金
  const marginUSDC = formatUnits(position.openMargin, 6);
  const size = Number(position.openSize);

  // 3. 计算预估盈亏 (Estimated PnL)
  const getSimulatedPnL = (targetPriceStr: string) => {
    if (!targetPriceStr) return 0;
    const targetPrice = parseFloat(targetPriceStr);
    const pnlPerUnit = position.isShort
      ? entryPrice - targetPrice
      : targetPrice - entryPrice;
    return pnlPerUnit * size;
  };

  /**
   * 提交平仓请求
   */
  const handleClose = async () => {
    try {
      if (!closePrice) return;

      const closeOrder = {
        isSell: !position.isShort, // Close long = Sell, Close short = Buy
        oType: ORDER_TYPE.Limit,
        size: position.openSize,
        price: parseUnits(closePrice, PX_DECIMALS),
      };

      console.log('Closing position:', tokenId, closeOrder);

      writeContract({
        address: position.pool as `0x${string}`,
        abi: POOL_ABI,
        functionName: 'closePosition',
        args: [tokenId, closeOrder],
      });

      toast.loading('平仓请求已提交，等待确认...');
      // 理想情况下等待 isSuccess 后再关闭弹窗，为了体验此处先关闭
      setShowCloseModal(false);
    } catch (error: any) {
      console.error('Close Error:', error);
      toast.error('平仓失败: ' + (error.message || 'Unknown error'));
    }
  };

  return (
    <>
      <div className="bg-bedrock-800/40 backdrop-blur-md border border-white/5 rounded-2xl p-6 transition-all shadow-lg hover:shadow-accent-purple/10 hover:border-accent-purple/30">
        <div className="flex items-start justify-between mb-5">
          <div className="flex items-center gap-3">
            <div className={`p-2.5 rounded-xl shadow-inner ${position.isShort
              ? 'bg-red-500/10 text-red-500 shadow-red-900/20'
              : 'bg-green-500/10 text-green-500 shadow-green-900/20'
              }`}>
              {position.isShort ? <TrendingDown size={22} /> : <TrendingUp size={22} />}
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className={`font-bold text-lg ${position.isShort ? 'text-red-400' : 'text-green-400'
                  }`}>
                  {position.isShort ? t.trading.short : t.trading.long}
                </span>
                <span className="text-xs px-2 py-0.5 rounded-full bg-gray-700 text-gray-400 border border-gray-600">
                  #{tokenId.toString()}
                </span>
              </div>
              <div className="text-xs text-gray-500 mt-1 flex items-center gap-1">
                {t.positions.status[position.status as 0 | 1 | 2 | 3 | 4 | 5]}
                {position.status === 2 && <span className="w-2 h-2 rounded-full bg-green-500 animate-pulse" />}
              </div>
            </div>
          </div>

          {position.status === 2 && (
            <button
              onClick={() => setShowCloseModal(true)}
              className="px-4 py-1.5 rounded-lg border border-red-500/30 text-red-400 hover:bg-red-500/10 hover:border-red-500/50 transition-all text-sm font-medium"
            >
              {t.positions.close}
            </button>
          )}
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 bg-bedrock-900/50 p-4 rounded-xl border border-white/5">
          <div>
            <div className="text-xs text-gray-500 mb-1">{t.positions.size}</div>
            <div className="font-mono font-semibold text-white">{size}</div>
          </div>
          <div>
            <div className="text-xs text-gray-500 mb-1">{t.positions.entry}</div>
            <div className="font-mono font-semibold text-white">${entryPrice.toFixed(2)}</div>
          </div>
          <div>
            <div className="text-xs text-gray-500 mb-1">{t.positions.margin}</div>
            <div className="font-mono font-semibold text-white">{marginUSDC} <span className="text-xs text-gray-600">USDC</span></div>
          </div>
          <div>
            <div className="text-xs text-gray-500 mb-1">{t.positions.leverage}</div>
            <div className="font-mono font-semibold text-blue-300">
              {marginUSDC && parseFloat(marginUSDC) > 0
                ? ((size * entryPrice) / parseFloat(marginUSDC)).toFixed(2)
                : 'ERROR'}x
            </div>
          </div>
        </div>
      </div>

      {/* Close Modal */}
      {showCloseModal && (
        <div className="fixed inset-0 bg-black/80 backdrop-blur-sm flex items-center justify-center z-50 p-4 animate-in fade-in duration-200">
          <div className="card max-w-md w-full border border-gray-700 bg-gray-800 shadow-2xl scale-100">
            <div className="flex items-center justify-between mb-6 border-b border-gray-700 pb-4">
              <h3 className="text-xl font-bold flex items-center gap-2">
                <ShieldAlert className="text-red-500" size={24} />
                {t.positions.closeModalTitle}
              </h3>
              <button
                onClick={() => setShowCloseModal(false)}
                className="text-gray-400 hover:text-white p-1 hover:bg-gray-700 rounded transition-colors"
              >
                <X size={24} />
              </button>
            </div>

            <div className="space-y-6">
              <div>
                <label className="label text-gray-300">{t.positions.closePrice} (USD)</label>
                <div className="relative">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500">$</span>
                  <input
                    type="number"
                    className="input pl-7"
                    value={closePrice}
                    onChange={(e) => setClosePrice(e.target.value)}
                    placeholder={entryPrice.toFixed(2)}
                    step="0.01"
                    min="0.01"
                  />
                </div>
                <p className="text-xs text-gray-500 mt-2 flex justify-between">
                  <span>{t.positions.entry}: ${entryPrice.toFixed(2)}</span>
                  <span>{t.positions.size}: {size} units</span>
                </p>
              </div>

              <div className="bg-gray-900/50 rounded-lg p-4 space-y-2 text-sm border border-gray-700">
                {closePrice && (
                  <>
                    <div className="flex justify-between items-center">
                      <span className="text-gray-400">{t.positions.pnl}:</span>
                      <span className={`font-mono text-lg font-bold ${getSimulatedPnL(closePrice) >= 0 ? 'text-green-500' : 'text-red-500'
                        }`}>
                        {getSimulatedPnL(closePrice) >= 0 ? '+' : ''}
                        ${getSimulatedPnL(closePrice).toFixed(2)}
                      </span>
                    </div>
                  </>
                )}
                <div className="text-xs text-gray-500 pt-2 border-t border-gray-700 mt-2">
                  注意：如果不完全成交，剩余部分将保留在持仓中。
                </div>
              </div>

              <button
                onClick={handleClose}
                disabled={!closePrice || isConfirming}
                className="w-full btn-primary bg-red-600 hover:bg-red-700 border-none py-3 text-lg"
              >
                {isConfirming ? t.trading.confirming : t.positions.confirmClose}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

