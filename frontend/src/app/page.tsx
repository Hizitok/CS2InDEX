'use client';

import { TradingInterface } from '@/components/trading/TradingInterface';
import { PositionsList } from '@/components/positions/PositionsList';
import { VaultBalance } from '@/components/vault/VaultBalance';
import { MarketOverview } from '@/components/market/MarketOverview';
import { useAccount } from 'wagmi';

export default function HomePage() {
  const { isConnected } = useAccount();

  if (!isConnected) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[60vh] text-center">
        <h1 className="text-5xl font-bold mb-6 bg-gradient-to-r from-primary-400 to-primary-600 bg-clip-text text-transparent">
          CS2InDEX
        </h1>
        <p className="text-xl text-gray-300 mb-8 max-w-2xl">
          Decentralized Perpetual Trading for CS2 Items
        </p>
        <div className="card max-w-md">
          <p className="text-gray-400 mb-4">
            Connect your wallet to start trading CS2 item perpetual contracts with up to 6x leverage
          </p>
          <div className="flex flex-col gap-4">
            <div className="flex items-center gap-2 text-sm text-gray-400">
              <span className="text-primary-500">✓</span>
              <span>On-chain order book</span>
            </div>
            <div className="flex items-center gap-2 text-sm text-gray-400">
              <span className="text-primary-500">✓</span>
              <span>NFT-based positions</span>
            </div>
            <div className="flex items-center gap-2 text-sm text-gray-400">
              <span className="text-primary-500">✓</span>
              <span>Automated liquidations</span>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Market Overview */}
      <MarketOverview />

      {/* Main Trading Area */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Vault Balance */}
        <div className="lg:col-span-1">
          <VaultBalance />
        </div>

        {/* Trading Interface */}
        <div className="lg:col-span-2">
          <TradingInterface />
        </div>
      </div>

      {/* Positions */}
      <PositionsList />
    </div>
  );
}
