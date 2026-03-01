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
import { useWriteContract, useWaitForTransactionReceipt, useReadContract } from 'wagmi';
import { POOL_ABI, PX_DECIMALS, ORDER_TYPE } from '@/config/contracts';
import toast from 'react-hot-toast';
import { TrendingUp, TrendingDown, X, ShieldAlert, Ban, Coins } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';

/**
 * 持仓数据结构
 * @interface Position
 */
interface Position {
  positionID: bigint;
  pool: string;
  isShort: boolean;
  status: number; // 0=none,1=pendingOpen,2=open,3=pendingClose,4=liquidating,5=closed,6=settled
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

  // For pendingOpen positions, fetch the limit price from the order book
  const { data: rawOrderPrice } = useReadContract({
    address: position.pool as `0x${string}`,
    abi: POOL_ABI,
    functionName: 'getOrderPrice',
    args: [tokenId],
    query: { enabled: position.status === 1 },
  });
  // Convert raw on-chain price (6 decimals) to human-readable; null if not yet loaded
  const orderBookPrice: number | null =
    rawOrderPrice != null ? Number(rawOrderPrice) / 10 ** PX_DECIMALS : null;

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
  // Human-readable size (raw on-chain value is 1e6-scaled)
  const size = Number(formatUnits(position.openSize, PX_DECIMALS));

  // 3a. 格式化 size 字段为人类可读 (6 decimals → display)
  const fmtSz = (n: bigint) => Number(formatUnits(n, PX_DECIMALS)).toFixed(2);

  // Size 显示格式:
  //   pendingOpen  (1): openSize / pendingSize  (已成交 / 剩余委托)
  //   pendingClose (3): closeSize / openSize    (平仓量 / 持仓量)
  //   其余状态        : openSize
  const sizeDisplay =
    position.status === 1
      ? `${fmtSz(position.openSize)} / ${fmtSz(position.pendingSize)}`
      : position.status === 3
      ? `${fmtSz(position.closeSize)} / ${fmtSz(position.openSize)}`
      : fmtSz(position.openSize);

  // 3. 计算预估盈亏 (Estimated PnL)
  const getSimulatedPnL = (targetPriceStr: string) => {
    if (!targetPriceStr) return 0;
    const targetPrice = parseFloat(targetPriceStr);
    const pnlPerUnit = position.isShort
      ? entryPrice - targetPrice
      : targetPrice - entryPrice;
    return pnlPerUnit * size;
  };

  /** 撤单 (pendingOpen → closed) */
  const handleCancel = () => {
    writeContract({
      address: position.pool as `0x${string}`,
      abi: POOL_ABI,
      functionName: 'cancelOrder',
      args: [tokenId],
    });
    toast.loading('撤单请求已提交，等待确认...');
  };

  /** 结算盈亏 (closed → settled) */
  const handleSettle = () => {
    writeContract({
      address: position.pool as `0x${string}`,
      abi: POOL_ABI,
      functionName: 'settlePnL',
      args: [tokenId],
    });
    toast.loading('结算请求已提交，等待确认...');
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
                {t.positions.status[position.status as 0 | 1 | 2 | 3 | 4 | 5 | 6]}
                {position.status === 2 && <span className="w-2 h-2 rounded-full bg-green-500 animate-pulse" />}
              </div>
            </div>
          </div>

          <div className="flex gap-2">
            {/* Cancel: pendingOpen or pendingClose */}
            {(position.status === 1 || position.status === 3) && (
              <button
                onClick={handleCancel}
                disabled={isConfirming}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-yellow-500/30 text-yellow-400 hover:bg-yellow-500/10 hover:border-yellow-500/50 transition-all text-sm font-medium disabled:opacity-50"
              >
                <Ban size={14} />
                {t.positions.cancel}
              </button>
            )}
            {/* Close: open */}
            {position.status === 2 && (
              <button
                onClick={() => setShowCloseModal(true)}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-red-500/30 text-red-400 hover:bg-red-500/10 hover:border-red-500/50 transition-all text-sm font-medium"
              >
                <X size={14} />
                {t.positions.close}
              </button>
            )}
            {/* Settle PnL: closed */}
            {position.status === 5 && (
              <button
                onClick={handleSettle}
                disabled={isConfirming}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-blue-500/30 text-blue-400 hover:bg-blue-500/10 hover:border-blue-500/50 transition-all text-sm font-medium disabled:opacity-50"
              >
                <Coins size={14} />
                {t.positions.settle}
              </button>
            )}
          </div>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 bg-bedrock-900/50 p-4 rounded-xl border border-white/5">
          <div>
            <div className="text-xs text-gray-500 mb-1">
              {t.positions.size}
              {position.status === 1 && <span className="ml-1 text-gray-600">(filled/pending)</span>}
              {position.status === 3 && <span className="ml-1 text-gray-600">(closing/open)</span>}
            </div>
            <div className="font-mono font-semibold text-white">{sizeDisplay}</div>
          </div>
          <div>
            <div className="text-xs text-gray-500 mb-1">
              {position.status === 1 ? 'Order Price' : t.positions.entry}
            </div>
            <div className="font-mono font-semibold text-white">
              {position.status === 1
                ? (orderBookPrice !== null ? `$${orderBookPrice.toFixed(2)}` : '—')
                : `$${entryPrice.toFixed(2)}`}
            </div>
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
        <div className="fixed inset-0 bg-black/75 backdrop-blur-sm flex items-center justify-center z-50 p-4">
          <div className="bg-bedrock-800 border border-white/10 rounded-2xl shadow-2xl w-full max-w-md">
            {/* Header */}
            <div className="flex items-center justify-between px-6 pt-5 pb-4 border-b border-white/10">
              <h3 className="text-base font-semibold flex items-center gap-2 text-white">
                <ShieldAlert className="text-red-400" size={18} />
                {t.positions.closeModalTitle}
              </h3>
              <button
                onClick={() => setShowCloseModal(false)}
                className="text-gray-500 hover:text-white p-1 hover:bg-white/10 rounded-lg transition-colors"
              >
                <X size={18} />
              </button>
            </div>

            <div className="px-6 py-5 space-y-5">
              {/* Position summary */}
              <div className="flex justify-between text-sm text-gray-400">
                <span>{t.positions.entry}: <span className="text-white font-mono">${entryPrice.toFixed(2)}</span></span>
                <span>{t.positions.size}: <span className="text-white font-mono">{fmtSz(position.openSize)}</span></span>
              </div>

              {/* Price input */}
              <div>
                <label className="block text-xs font-medium text-gray-400 mb-2">
                  {t.positions.closePrice} (USD)
                </label>
                <div className="flex items-center bg-bedrock-900 border border-white/10 rounded-xl focus-within:border-accent-purple/60 transition-colors">
                  <span className="pl-4 text-gray-500 select-none">$</span>
                  <input
                    autoFocus
                    type="number"
                    className="flex-1 bg-transparent text-white font-mono px-2 py-3 outline-none placeholder-gray-600 text-sm"
                    value={closePrice}
                    onChange={(e) => setClosePrice(e.target.value)}
                    placeholder={entryPrice.toFixed(2)}
                    step="0.01"
                    min="0.01"
                  />
                </div>
                {/* Quick-select buttons */}
                <div className="flex gap-2 mt-2">
                  {[-2, -1, 1, 2].map(pct => {
                    const p = (entryPrice * (1 + pct / 100)).toFixed(2);
                    return (
                      <button
                        key={pct}
                        onClick={() => setClosePrice(p)}
                        className={`flex-1 text-xs py-1.5 rounded-lg border transition-colors font-mono ${
                          pct < 0
                            ? 'border-red-500/30 text-red-400 hover:bg-red-500/10'
                            : 'border-green-500/30 text-green-400 hover:bg-green-500/10'
                        }`}
                      >
                        {pct > 0 ? '+' : ''}{pct}%
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* PnL preview */}
              <div className="bg-bedrock-900/60 rounded-xl border border-white/5 px-4 py-3">
                <div className="flex justify-between items-center">
                  <span className="text-xs text-gray-500">{t.positions.pnl}</span>
                  {closePrice ? (
                    <span className={`font-mono font-bold text-base ${
                      getSimulatedPnL(closePrice) >= 0 ? 'text-green-400' : 'text-red-400'
                    }`}>
                      {getSimulatedPnL(closePrice) >= 0 ? '+' : ''}
                      ${getSimulatedPnL(closePrice).toFixed(2)}
                    </span>
                  ) : (
                    <span className="text-gray-600 text-sm">—</span>
                  )}
                </div>
              </div>

              {/* Confirm button */}
              <button
                onClick={handleClose}
                disabled={!closePrice || isConfirming}
                className="w-full py-3 rounded-xl font-semibold text-sm transition-all bg-red-600 hover:bg-red-500 disabled:opacity-40 disabled:cursor-not-allowed text-white"
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

