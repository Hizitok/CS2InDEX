'use client';

import { useEffect, useRef, useMemo } from 'react';
import { useReadContract } from 'wagmi';
import { createChart, ColorType, IChartApi, CandlestickSeries, Time } from 'lightweight-charts';
import { useLanguage } from '@/contexts/LanguageContext';
import { POOL_ABI, PX_DECIMALS } from '@/config/contracts';

// ── Seeded LCG PRNG — same seed → same chart, different pool → different pattern ──
function makeRng(seed: string) {
    let s = 0;
    for (let i = 0; i < seed.length; i++) {
        s = (s * 31 + seed.charCodeAt(i)) >>> 0;
    }
    return () => {
        s = (s * 1664525 + 1013904223) >>> 0;
        return s / 0x100000000;
    };
}

function generateCandleData(
    basePrice: number,
    seed: string,
): { time: Time; open: number; high: number; low: number; close: number }[] {
    const rand = makeRng(seed);
    const data = [];
    let ts = new Date('2024-01-01').getTime() / 1000;
    let price = basePrice;
    const vol = basePrice * 0.006; // ~0.6% daily volatility, scales with price

    for (let i = 0; i < 120; i++) {
        const open = price;
        const close = Math.max(open + (rand() - 0.48) * vol, open * 0.01);
        const high  = Math.max(open, close) + rand() * vol * 0.4;
        const low   = Math.min(open, close) - rand() * vol * 0.4;
        data.push({ time: ts as Time, open, high, low, close });
        price = close;
        ts += 86400;
    }
    return data;
}

interface PriceChartProps {
    poolAddress: `0x${string}`;
    poolName?: string;
}

export function PriceChart({ poolAddress, poolName }: PriceChartProps) {
    const chartContainerRef = useRef<HTMLDivElement>(null);
    const chartRef          = useRef<IChartApi | null>(null);
    const { t } = useLanguage();

    // Read oracle price as the chart's base price
    const { data: oraclePriceRaw } = useReadContract({
        address: poolAddress,
        abi: POOL_ABI,
        functionName: 'oraclePrice',
        query: { enabled: !!poolAddress },
    });

    const { data: lastPriceRaw } = useReadContract({
        address: poolAddress,
        abi: POOL_ABI,
        functionName: 'getLastPrice',
        query: { enabled: !!poolAddress },
    });

    // Last price if available, fall back to oracle price
    const basePrice = useMemo(() => {
        const lp = lastPriceRaw as bigint | undefined;
        const op = oraclePriceRaw as bigint | undefined;
        const raw = lp && lp > 0n ? lp : op;
        if (!raw) return null;
        return Number(raw) / 10 ** PX_DECIMALS;
    }, [lastPriceRaw, oraclePriceRaw]);

    useEffect(() => {
        if (!chartContainerRef.current || basePrice === null) return;

        // Tear down previous chart before rebuilding
        if (chartRef.current) {
            chartRef.current.remove();
            chartRef.current = null;
        }

        const chart = createChart(chartContainerRef.current, {
            layout: {
                background: { type: ColorType.Solid, color: 'transparent' },
                textColor: '#9ca3af',
            },
            grid: {
                vertLines: { color: 'rgba(255, 255, 255, 0.05)' },
                horzLines: { color: 'rgba(255, 255, 255, 0.05)' },
            },
            width: chartContainerRef.current.clientWidth,
            height: 400,
            timeScale: { timeVisible: true, secondsVisible: false },
        });

        const candleSeries = chart.addSeries(CandlestickSeries, {
            upColor:       '#22c55e',
            downColor:     '#ef4444',
            borderVisible: false,
            wickUpColor:   '#22c55e',
            wickDownColor: '#ef4444',
        });

        candleSeries.setData(generateCandleData(basePrice, poolAddress));
        chart.timeScale().fitContent();
        chartRef.current = chart;

        const handleResize = () => {
            if (chartContainerRef.current && chartRef.current) {
                chartRef.current.applyOptions({ width: chartContainerRef.current.clientWidth });
            }
        };
        window.addEventListener('resize', handleResize);

        return () => {
            window.removeEventListener('resize', handleResize);
            chartRef.current?.remove();
            chartRef.current = null;
        };
    }, [poolAddress, basePrice]);

    return (
        <div className="glass-card p-6 rounded-xl border border-white/10 mb-6">
            <div className="flex items-center justify-between mb-4">
                <h3 className="text-xl font-bold text-white flex items-center gap-2">
                    <span className="w-2 h-2 bg-green-500 rounded-full animate-pulse" />
                    {poolName ? `${poolName}` : t.chart.title}
                </h3>
                <div className="flex gap-2">
                    {(['24H', '1W', '1M'] as const).map(tf => (
                        <button
                            key={tf}
                            className="px-3 py-1 bg-white/5 hover:bg-white/10 rounded text-xs text-gray-400"
                        >
                            {t.chart.timeframes[tf]}
                        </button>
                    ))}
                </div>
            </div>

            {basePrice === null ? (
                <div className="w-full h-[400px] flex items-center justify-center text-gray-500 text-sm">
                    Loading chart...
                </div>
            ) : (
                <div ref={chartContainerRef} className="w-full h-[400px]" />
            )}
        </div>
    );
}
