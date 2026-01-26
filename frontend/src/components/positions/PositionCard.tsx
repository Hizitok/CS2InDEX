'use client';

import { useState } from 'react';
import { formatUnits } from 'viem';
import { useWriteContract } from 'wagmi';
import { POOL_ABI } from '@/config/contracts';
import toast from 'react-hot-toast';
import { TrendingUp, TrendingDown, X } from 'lucide-react';

interface Position {
  pool: string;
  positionID: bigint;
  status: number;
  isShort: boolean;
  openMargin: bigint;
  pendingSize: bigint;
  openSize: bigint;
  closeSize: bigint;
  openAmount: bigint;
  closeAmount: bigint;
}

interface PositionCardProps {
  tokenId: bigint;
  position: Position;
}

const STATUS_NAMES = ['None', 'Pending Open', 'Open', 'Pending Close', 'Force Close', 'Closed'];

export function PositionCard({ tokenId, position }: PositionCardProps) {
  const [showCloseModal, setShowCloseModal] = useState(false);
  const [closePrice, setClosePrice] = useState('');

  const { writeContract } = useWriteContract();

  // Calculate average entry price
  const entryPrice = position.openSize > 0n
    ? Number(position.openAmount) / Number(position.openSize) / 100
    : 0;

  // Format values
  const marginUSDC = formatUnits(position.openMargin, 6);
  const size = Number(position.openSize);

  const handleClose = async () => {
    try {
      const closeOrder = {
        isSell: !position.isShort, // Close long with sell, close short with buy
        oType: 1, // Limit order
        size: position.openSize,
        priceX100: BigInt(Math.floor(parseFloat(closePrice) * 100)),
        margin: 0n,
      };

      writeContract({
        address: position.pool as `0x${string}`,
        abi: POOL_ABI,
        functionName: 'closePosition',
        args: [tokenId, closeOrder],
      });

      toast.success('Close order submitted!');
      setShowCloseModal(false);
    } catch (error: any) {
      toast.error(error.message || 'Failed to close position');
    }
  };

  return (
    <>
      <div className="bg-gray-700/50 rounded-lg p-4 hover:bg-gray-700/70 transition-colors">
        <div className="flex items-start justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className={`p-2 rounded-lg ${position.isShort ? 'bg-red-600/20' : 'bg-green-600/20'}`}>
              {position.isShort ? (
                <TrendingDown className="text-red-500" size={20} />
              ) : (
                <TrendingUp className="text-green-500" size={20} />
              )}
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="font-semibold">
                  {position.isShort ? 'Short' : 'Long'}
                </span>
                <span className="text-sm px-2 py-1 rounded bg-gray-600 text-gray-300">
                  #{tokenId.toString()}
                </span>
              </div>
              <div className="text-sm text-gray-400 mt-1">
                Status: {STATUS_NAMES[position.status]}
              </div>
            </div>
          </div>

          {position.status === 2 && ( // Status 2 = Open
            <button
              onClick={() => setShowCloseModal(true)}
              className="text-red-400 hover:text-red-300 transition-colors"
            >
              Close
            </button>
          )}
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div>
            <div className="text-sm text-gray-400">Size</div>
            <div className="font-semibold">{size}</div>
          </div>
          <div>
            <div className="text-sm text-gray-400">Entry Price</div>
            <div className="font-semibold">${entryPrice.toFixed(2)}</div>
          </div>
          <div>
            <div className="text-sm text-gray-400">Margin</div>
            <div className="font-semibold">{marginUSDC} USDC</div>
          </div>
          <div>
            <div className="text-sm text-gray-400">Leverage</div>
            <div className="font-semibold">
              {((size * entryPrice) / parseFloat(marginUSDC)).toFixed(2)}x
            </div>
          </div>
        </div>
      </div>

      {/* Close Modal */}
      {showCloseModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="card max-w-md w-full">
            <div className="flex items-center justify-between mb-6">
              <h3 className="text-xl font-bold">Close Position</h3>
              <button
                onClick={() => setShowCloseModal(false)}
                className="text-gray-400 hover:text-white"
              >
                <X size={24} />
              </button>
            </div>

            <div className="space-y-4">
              <div>
                <label className="label">Close Price (USD)</label>
                <input
                  type="number"
                  className="input"
                  value={closePrice}
                  onChange={(e) => setClosePrice(e.target.value)}
                  placeholder={entryPrice.toFixed(2)}
                  step="0.01"
                  min="0.01"
                />
                <p className="text-sm text-gray-400 mt-2">
                  Entry: ${entryPrice.toFixed(2)}
                </p>
              </div>

              <div className="bg-gray-700/50 rounded-lg p-4 space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-gray-400">Position Size:</span>
                  <span>{size} units</span>
                </div>
                {closePrice && (
                  <>
                    <div className="flex justify-between">
                      <span className="text-gray-400">Est. PnL:</span>
                      <span className={
                        (position.isShort ? entryPrice - parseFloat(closePrice) : parseFloat(closePrice) - entryPrice) > 0
                          ? 'text-green-500'
                          : 'text-red-500'
                      }>
                        ${((position.isShort ? entryPrice - parseFloat(closePrice) : parseFloat(closePrice) - entryPrice) * size).toFixed(2)}
                      </span>
                    </div>
                  </>
                )}
              </div>

              <button
                onClick={handleClose}
                disabled={!closePrice}
                className="w-full btn-primary"
              >
                Confirm Close
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
