'use client';

import { MarketOverview } from '@/components/market/MarketOverview';
import { useLanguage } from '@/contexts/LanguageContext';

export default function MarketsPage() {
    const { t } = useLanguage();
    return (
        <div className="container mx-auto px-4 pt-24 pb-20 relative min-h-screen">
            {/* Background Glow */}
            <div className="absolute top-20 left-10 w-[400px] h-[400px] bg-accent-cyan/10 rounded-full blur-[120px] -z-10 pointer-events-none" />

            <h1 className="text-4xl font-bold mb-8 flex items-center gap-3">
                <span className="text-gradient hover:scale-105 transition-transform cursor-default">
                    {t.market.title}
                </span>
            </h1>
            <MarketOverview />
        </div>
    );
}
