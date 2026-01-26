'use client';

import { useState } from 'react';
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseUnits } from 'viem';
import toast from 'react-hot-toast';
import { POOL_ABI } from '@/config/contracts';
import { TrendingUp, TrendingDown } from 'lucide-react';

const ITEMS = [
  { name: 'AK47-Redline', pool: '0x...' },
  { name: 'AWP-Dragon Lore', pool: '0x...' },
  { name: 'M4A4-Howl', pool: '0x...' },
];

export function TradingInterface() {
  const { address } = useAccount();
  const [selectedItem, setSelectedItem] = useState(ITEMS[0]);
  const [isLong, setIsLong] = useState(true);
  const [size, setSize] = useState('');
  const [price, setPrice] = useState('');
  const [margin, setMargin] = useState('');
  const [orderType, setOrderType] = useState<'Limit' | 'Market'>('Limit');

  const { writeContract, data: hash } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!address) {
      toast.error('Please connect your wallet');
      return;
    }

    try {
      const order = {
        isSell: !isLong, // Long = buy, Short = sell
        oType: orderType === 'Limit' ? 1 : 0, // 0 = Market, 1 = Limit
        size: BigInt(size),
        priceX100: orderType === 'Limit' ? parseUnits(price, 2) : BigInt(0),
        margin: parseUnits(margin, 6), // USDC has 6 decimals
      };

      writeContract({
        address: selectedItem.pool as `0x${string}`,
        abi: POOL_ABI,
        functionName: 'newOrder',
        args: [order],
      });

      toast.success('Order submitted!');
    } catch (error: any) {
      toast.error(error.message || 'Transaction failed');
    }
  };

  const leverage = margin && size && price
    ? ((parseFloat(size) * parseFloat(price)) / parseFloat(margin)).toFixed(2)
    : '0';

  return (
    <div className="card">
      <h2 className="text-2xl font-bold mb-6">Open Position</h2>

      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Item Selection */}
        <div>
          <label className="label">Select Item</label>
          <select
            className="input"
            value={selectedItem.name}
            onChange={(e) => setSelectedItem(ITEMS.find(i => i.name === e.target.value)!)}
          >
            {ITEMS.map(item => (
              <option key={item.name} value={item.name}>
                {item.name}
              </option>
            ))}
          </select>
        </div>

        {/* Long/Short Toggle */}
        <div>
          <label className="label">Direction</label>
          <div className="grid grid-cols-2 gap-4">
            <button
              type="button"
              onClick={() => setIsLong(true)}
              className={`py-3 rounded-lg font-semibold transition-colors flex items-center justify-center gap-2 ${
                isLong
                  ? 'bg-green-600 text-white'
                  : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              }`}
            >
              <TrendingUp size={20} />
              Long
            </button>
            <button
              type="button"
              onClick={() => setIsLong(false)}
              className={`py-3 rounded-lg font-semibold transition-colors flex items-center justify-center gap-2 ${
                !isLong
                  ? 'bg-red-600 text-white'
                  : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              }`}
            >
              <TrendingDown size={20} />
              Short
            </button>
          </div>
        </div>

        {/* Order Type */}
        <div>
          <label className="label">Order Type</label>
          <div className="grid grid-cols-2 gap-4">
            <button
              type="button"
              onClick={() => setOrderType('Limit')}
              className={`py-2 rounded-lg font-medium transition-colors ${
                orderType === 'Limit'
                  ? 'bg-primary-600 text-white'
                  : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              }`}
            >
              Limit
            </button>
            <button
              type="button"
              onClick={() => setOrderType('Market')}
              className={`py-2 rounded-lg font-medium transition-colors ${
                orderType === 'Market'
                  ? 'bg-primary-600 text-white'
                  : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              }`}
            >
              Market
            </button>
          </div>
        </div>

        {/* Size */}
        <div>
          <label className="label">Size (units)</label>
          <input
            type="number"
            className="input"
            value={size}
            onChange={(e) => setSize(e.target.value)}
            placeholder="10"
            required
            min="1"
            step="1"
          />
        </div>

        {/* Price (only for limit orders) */}
        {orderType === 'Limit' && (
          <div>
            <label className="label">Price (USD)</label>
            <input
              type="number"
              className="input"
              value={price}
              onChange={(e) => setPrice(e.target.value)}
              placeholder="500.00"
              required
              min="0.01"
              step="0.01"
            />
          </div>
        )}

        {/* Margin */}
        <div>
          <label className="label">Margin (USDC)</label>
          <input
            type="number"
            className="input"
            value={margin}
            onChange={(e) => setMargin(e.target.value)}
            placeholder="1000.00"
            required
            min="0.01"
            step="0.01"
          />
          <p className="text-sm text-gray-400 mt-2">
            Max leverage: 6x
          </p>
        </div>

        {/* Info */}
        {size && margin && (orderType === 'Market' || price) && (
          <div className="bg-gray-700/50 rounded-lg p-4 space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-gray-400">Leverage:</span>
              <span className={`font-semibold ${parseFloat(leverage) > 6 ? 'text-red-500' : 'text-white'}`}>
                {leverage}x
                {parseFloat(leverage) > 6 && ' ⚠️ Too high'}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Position Value:</span>
              <span className="text-white">
                ${orderType === 'Market' ? 'Market Price' : (parseFloat(size) * parseFloat(price)).toFixed(2)}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Liquidation Price:</span>
              <span className="text-red-400">
                Calculated after open
              </span>
            </div>
          </div>
        )}

        {/* Submit */}
        <button
          type="submit"
          disabled={isConfirming || parseFloat(leverage) > 6}
          className={`w-full py-4 rounded-lg font-bold text-lg transition-colors ${
            isLong
              ? 'bg-green-600 hover:bg-green-700 text-white'
              : 'bg-red-600 hover:bg-red-700 text-white'
          } disabled:opacity-50 disabled:cursor-not-allowed`}
        >
          {isConfirming
            ? 'Confirming...'
            : `Open ${isLong ? 'Long' : 'Short'} Position`
          }
        </button>
      </form>
    </div>
  );
}
