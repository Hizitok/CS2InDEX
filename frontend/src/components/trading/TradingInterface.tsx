'use client';

/**
 * @fileoverview 交易核心组件 (Trading Interface)
 * 负责处理用户开仓操作 (Long/Short)，包含限价/市价单逻辑、杠杆计算及风险校验。
 * 遵循 Google TypeScript Style Guide。
 *
 * @author Senior Architect
 */

import { useState, useMemo, useEffect } from 'react';
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseUnits, formatUnits } from 'viem';
import toast from 'react-hot-toast';
import { POOL_ABI, PX_DECIMALS, ORDER_TYPE, TAKER_FEE } from '@/config/contracts';
import { TrendingUp, TrendingDown, Info, Wallet, Calculator } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { useLanguage } from '@/contexts/LanguageContext';
import { usePool } from '@/contexts/PoolContext';

const MAX_LEVERAGE = 10; // 最大杠杆倍数

/**
 * 交易界面组件
 * 提供开仓、杠杆预览、风险提示等功能。
 */
export function TradingInterface() {
  const { address } = useAccount();
  const { t } = useLanguage();
  const { selectedPool } = usePool();

  // 组件状态
  const selectedItem = selectedPool;
  const [isLong, setIsLong] = useState<boolean>(true);
  const [size, setSize] = useState<string>('1'); // 数量 (Default 1)
  const [price, setPrice] = useState<string>('100'); // 价格 (Limit Order) - Default 100 for better demo
  const [margin, setMargin] = useState<string>(''); // 保证金 (USDC)
  const [leverage, setLeverage] = useState<number>(2); // Default 2x
  const [orderType, setOrderType] = useState<'Limit' | 'Market'>('Limit');
  const [manualMargin, setManualMargin] = useState<boolean>(false); // Track if user edited margin

  // 合约交互 Hooks
  const { writeContract, data: hash, error: writeError } = useWriteContract();
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash });

  // ---------------------------------------------------------------------------
  // Auto-Calculation Logic
  // ---------------------------------------------------------------------------

  // Calculate Margin based on Size & Leverage (when Size or Leverage changes, and NOT manual margin mode)
  useEffect(() => {
    if (manualMargin) return;

    if (!size || (orderType === 'Limit' && !price)) return;

    const effectivePrice = orderType === 'Limit' ? parseFloat(price) : 100; // Mock 100 if Market for now
    if (isNaN(effectivePrice) || effectivePrice <= 0) return;

    const positionValue = parseFloat(size) * effectivePrice;
    if (isNaN(positionValue)) return;

    const requiredMargin = positionValue / leverage;
    setMargin(requiredMargin.toFixed(2));
  }, [size, price, leverage, orderType, manualMargin]);

  // If user changes Leverage Slider -> Reset Manual Mode -> Trigger Effect
  const handleLeverageChange = (newLeverage: number) => {
    setManualMargin(false);
    setLeverage(newLeverage);
  };

  // If user types Margin -> Set Manual Mode -> Update Leverage Display
  const handleMarginChange = (newMargin: string) => {
    setMargin(newMargin);
    setManualMargin(true);

    // Reverse calc leverage for display
    const m = parseFloat(newMargin);
    const s = parseFloat(size);
    const p = orderType === 'Limit' ? parseFloat(price || '0') : 100;

    if (m > 0 && s > 0 && p > 0) {
      const impliedLev = (s * p) / m;
      // Don't update state `leverage` directly to strictly follow slider, 
      // but we could visually show it. For now, let's just let it drift visually or update state?
      // Better to update state so slider moves? 
      // If we update state, the effect triggers and overwrites margin. Infinite loop risk if not careful.
      // So we won't update `leverage` state here, just let it be "Custom".
    }
  };

  /**
   * Derived Calculations for UI
   */
  const derivedInfo = useMemo(() => {
    const s = parseFloat(size) || 0;
    const p = orderType === 'Limit' ? parseFloat(price || '0') : 100; // Mock current price
    const m = parseFloat(margin) || 0;

    const positionValue = s * p;
    const currentLeverage = m > 0 ? positionValue / m : 0;

    // Est. Liquidation Price
    // Long Liq = Entry * (1 - 1/Lev)
    // Short Liq = Entry * (1 + 1/Lev)
    let liqPrice = 0;
    if (currentLeverage > 0) {
      if (isLong) {
        liqPrice = p * (1 - 1 / currentLeverage);
      } else {
        liqPrice = p * (1 + 1 / currentLeverage);
      }
    }

    const tradingFee = positionValue * TAKER_FEE; // 0.5% taker fee
    const totalCost = m + tradingFee;

    return {
      leverage: currentLeverage,
      liqPrice: Math.max(0, liqPrice),
      fee: tradingFee,
      totalCost,
      isRisky: currentLeverage > MAX_LEVERAGE || currentLeverage < 1
    };
  }, [size, price, margin, isLong, orderType]);


  /**
   * 处理表单提交 (提交订单)
   */
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!address) {
      toast.error(t.trading.pleaseConnect);
      return;
    }

    if (derivedInfo.isRisky && orderType === 'Limit') {
      toast.error(`Leverage abnormal (${derivedInfo.leverage.toFixed(2)}x). Max ${MAX_LEVERAGE}x`);
      return;
    }

    try {
      const marginAmount = parseUnits(margin, PX_DECIMALS);
      const pOrder = {
        isSell: !isLong,
        oType: orderType === 'Limit' ? ORDER_TYPE.Limit : ORDER_TYPE.Market,
        size: parseUnits(size, PX_DECIMALS),
        price: orderType === 'Limit' ? parseUnits(price, PX_DECIMALS) : BigInt(0),
      };

      console.log('Submitting Order:', { margin: marginAmount, pOrder });

      if (!selectedItem) {
        toast.error('No pool selected');
        return;
      }

      writeContract({
        address: selectedItem.address,
        abi: POOL_ABI,
        functionName: 'newOrder',
        args: [marginAmount, pOrder],
      });

      toast.loading(t.trading.confirmInWallet);
    } catch (error: unknown) {
      console.error('Order Error:', error);
      const errorMsg = error instanceof Error ? error.message : t.trading.unknownError;
      toast.error(`${t.trading.txFailed}: ${errorMsg}`);
    }
  };

  return (
    <div className="glass-card rounded-2xl p-6 h-full border border-white/5 bg-[#0a0a0a]/60 backdrop-blur-xl">
      <div className="flex justify-between items-center mb-6">
        <h2 className="text-xl font-bold text-white flex items-center gap-2">
          <Calculator className="text-accent-cyan" size={24} />
          {isLong ? t.trading.long : t.trading.short} {selectedItem?.name ?? '...'}
        </h2>

        {/* Leverage Display */}
        <div className={`px-3 py-1 rounded-full text-sm font-bold border ${derivedInfo.isRisky ? 'border-red-500 text-red-400 bg-red-500/10' : 'border-accent-cyan/30 text-accent-cyan bg-accent-cyan/10'
          }`}>
          {derivedInfo.leverage.toFixed(2)}x {t.trading.leverage}
        </div>
      </div>

      <form onSubmit={handleSubmit} className="space-y-6">

        {/* Direction Toggle (Segmented Control) */}
        <div className="bg-black/40 p-1 rounded-xl grid grid-cols-2 gap-1">
          <button
            type="button"
            onClick={() => setIsLong(true)}
            className={`py-3 rounded-lg font-bold text-sm transition-all flex items-center justify-center gap-2 ${isLong
              ? 'bg-green-500 text-white shadow-lg shadow-green-500/20'
              : 'text-gray-400 hover:text-white hover:bg-white/5'
              }`}
          >
            <TrendingUp size={16} />
            {t.trading.long}
          </button>
          <button
            type="button"
            onClick={() => setIsLong(false)}
            className={`py-3 rounded-lg font-bold text-sm transition-all flex items-center justify-center gap-2 ${!isLong
              ? 'bg-red-500 text-white shadow-lg shadow-red-500/20'
              : 'text-gray-400 hover:text-white hover:bg-white/5'
              }`}
          >
            <TrendingDown size={16} />
            {t.trading.short}
          </button>
        </div>

        {/* Order Type Tabs */}
        <div className="flex border-b border-white/10">
          {['Limit', 'Market'].map((type) => (
            <button
              key={type}
              type="button"
              onClick={() => setOrderType(type as 'Limit' | 'Market')}
              className={`pb-2 px-4 text-sm font-bold transition-all border-b-2 ${orderType === type
                ? 'border-accent-cyan text-white'
                : 'border-transparent text-gray-500 hover:text-gray-300'
                }`}
            >
              {type === 'Limit' ? t.trading.limit : t.trading.market}
            </button>
          ))}
        </div>

        {/* Price & Size Inputs */}
        <div className="space-y-4">
          {/* Price Input */}
          {orderType === 'Limit' && (
            <div className="space-y-1">
              <div className="flex justify-between text-xs text-gray-400">
                <span>{t.trading.price}</span>
                <span>{t.trading.oracle}: $102.50</span>
              </div>
              <div className="relative">
                <input
                  type="number"
                  className="w-full bg-black/40 border border-white/10 rounded-lg py-3 px-4 text-white font-mono focus:border-accent-cyan focus:outline-none transition-colors"
                  value={price}
                  onChange={(e) => setPrice(e.target.value)}
                />
                <span className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-500 text-xs">USDC</span>
              </div>
            </div>
          )}

          {/* Size Input */}
          <div className="space-y-1">
            <div className="flex justify-between text-xs text-gray-400">
              <span>{t.trading.size}</span>
              <span>{t.trading.max}: 100</span>
            </div>
            <div className="relative">
              <input
                type="number"
                className="w-full bg-black/40 border border-white/10 rounded-lg py-3 px-4 text-white font-mono focus:border-accent-cyan focus:outline-none transition-colors"
                value={size}
                onChange={(e) => setSize(e.target.value)}
              />
              <span className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-500 text-xs text-right">
                {t.trading.contracts} <br /> (Index)
              </span>
            </div>
          </div>
        </div>

        {/* Leverage Slider */}
        <div className="space-y-3 pt-2">
          <div className="flex justify-between items-center text-sm">
            <span className="text-gray-400">{t.trading.leverage}</span>
            <span className="text-accent-cyan font-bold">{leverage}x</span>
          </div>
          <input
            type="range"
            min="1"
            max="10"
            step="1"
            value={leverage}
            onChange={(e) => handleLeverageChange(parseInt(e.target.value))}
            className="w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-accent-cyan hover:accent-accent-cyan/80"
          />
          <div className="flex justify-between text-[10px] text-gray-500 px-1 font-mono">
            <span>1x</span>
            <span>2x</span>
            <span>3x</span>
            <span>4x</span>
            <span>5x</span>
            <span>6x</span>
            <span>7x</span>
            <span>8x</span>
            <span>9x</span>
            <span>10x</span>
          </div>
        </div>

        {/* Margin Input (Auto-calculated but editable) */}
        <div className="space-y-1">
          <div className="flex justify-between text-xs text-gray-400">
            <span>{t.trading.reqMargin}</span>
            <span className="text-accent-cyan">{t.trading.balance}: $5000.00</span>
          </div>
          <div className="relative">
            <input
              type="number"
              className={`w-full bg-black/40 border rounded-lg py-3 px-4 text-white font-mono focus:outline-none transition-colors ${manualMargin ? 'border-yellow-500/50' : 'border-white/10 focus:border-accent-cyan'
                }`}
              value={margin}
              onChange={(e) => handleMarginChange(e.target.value)}
            />
            <span className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-500 text-xs">USDC</span>
          </div>
          {manualMargin && <p className="text-[10px] text-yellow-500/80 pl-1">{t.trading.manualOverride}</p>}
        </div>

        {/* Order Summary Card */}
        <div className="bg-white/5 rounded-xl p-4 space-y-2 text-xs border border-white/5">
          <div className="flex justify-between">
            <span className="text-gray-500">{t.trading.entryPrice}</span>
            <span className="text-white font-mono">${orderType === 'Limit' ? price : t.trading.market}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-500">{t.trading.liqPrice}</span>
            <span className={`font-mono ${isLong ? 'text-red-400' : 'text-green-400'}`}>
              ${derivedInfo.liqPrice.toFixed(2)}
            </span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-500">{t.trading.fee} (0.5%)</span>
            <span className="text-gray-300 font-mono">${derivedInfo.fee.toFixed(2)}</span>
          </div>
          <div className="border-t border-white/10 my-2 pt-2 flex justify-between font-bold">
            <span className="text-gray-400">{t.trading.totalCost}</span>
            <span className="text-white font-mono">${derivedInfo.totalCost.toFixed(2)}</span>
          </div>
        </div>

        {/* Submit Button */}
        <motion.button
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
          type="submit"
          disabled={isConfirming || derivedInfo.isRisky || !selectedItem}
          className={`w-full py-4 rounded-xl font-bold text-lg transition-all ${isConfirming ? 'opacity-50 cursor-wait' : ''
            } ${isLong
              ? 'bg-green-500 hover:bg-green-400 text-black shadow-[0_0_20px_rgba(34,197,94,0.4)]'
              : 'bg-red-500 hover:bg-red-400 text-white shadow-[0_0_20px_rgba(239,68,68,0.4)]'
            } disabled:grayscale disabled:cursor-not-allowed`}
        >
          {isConfirming ? (
            <span className="flex items-center justify-center gap-2">
              <span className="loading loading-spinner loading-sm"></span>
              {t.trading.confirming}
            </span>
          ) : (
            `${isLong ? t.trading.buy : t.trading.sell} / ${isLong ? t.trading.long : t.trading.short} $CS2`
          )}
        </motion.button>
      </form>
    </div>
  );
}

