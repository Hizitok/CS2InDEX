'use client';

import * as React from 'react';
import { PositionsList } from '@/components/positions/PositionsList';
import { TradingInterface } from '@/components/trading/TradingInterface';
import { VaultBalance } from '@/components/vault/VaultBalance';
import { PriceChart } from '@/components/market/PriceChart';
import { OrderbookDepth } from '@/components/market/OrderbookDepth';
import { useLanguage } from '@/contexts/LanguageContext';
import { CONTRACTS } from '@/config/contracts';

export default function PositionsPage() {
    const { t } = useLanguage();
    const [activeTab, setActiveTab] = React.useState<'trade' | 'vault'>('trade');

    return (
        <div className="container mx-auto px-4 pt-24 pb-20 relative min-h-screen">
            {/* Background Glow */}
            <div className="absolute bottom-20 right-10 w-[400px] h-[400px] bg-accent-purple/10 rounded-full blur-[120px] -z-10 pointer-events-none" />

            <h1 className="text-4xl font-bold mb-8 flex items-center gap-3">
                <span className="text-gradient hover:scale-105 transition-transform cursor-default">
                    {t.nav.positions}
                </span>
            </h1>

            <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
                {/* Left Column: Trading & Vault (Tabbed) */}
                <div className="lg:col-span-4 space-y-6 order-2 lg:order-1">
                    <div className="sticky top-24">
                        <div className="glass-card rounded-xl p-1 mb-6 flex gap-1">
                            {['trade', 'vault'].map((tab) => (
                                <button
                                    key={tab}
                                    onClick={() => setActiveTab(tab as 'trade' | 'vault')}
                                    className={`flex-1 py-3 rounded-lg font-bold text-sm transition-all ${activeTab === tab
                                        ? 'bg-accent-cyan/10 text-accent-cyan shadow-[0_0_20px_rgba(34,211,238,0.1)]'
                                        : 'text-gray-500 hover:text-gray-300 hover:bg-white/5'
                                        }`}
                                >
                                    {tab === 'trade' ? t.nav.trade : t.vault.title}
                                </button>
                            ))}
                        </div>

                        <div className={activeTab === 'trade' ? 'block' : 'hidden'}>
                            <TradingInterface />
                        </div>
                        <div className={activeTab === 'vault' ? 'block' : 'hidden'}>
                            <VaultBalance />
                        </div>
                    </div>
                </div>

                {/* Right Column: Positions List (Wider) */}
                <div className="lg:col-span-8 order-1 lg:order-2">
                    <PriceChart />
                    <OrderbookDepth poolAddress={CONTRACTS.POOL} />
                    <PositionsList />
                </div>
            </div>
        </div>
    );
}
