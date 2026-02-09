'use client';

import { useEffect, useRef } from 'react';
import { createChart, ColorType, IChartApi, ISeriesApi, Time, CandlestickSeries } from 'lightweight-charts';
import { useLanguage } from '@/contexts/LanguageContext';

export function PriceChart() {
    const chartContainerRef = useRef<HTMLDivElement>(null);
    const chartRef = useRef<IChartApi | null>(null);
    const { t } = useLanguage();

    useEffect(() => {
        if (!chartContainerRef.current) return;

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
            timeScale: {
                timeVisible: true,
                secondsVisible: false,
            },
        });

        const candleSeries = chart.addSeries(CandlestickSeries, {
            upColor: '#22c55e',
            downColor: '#ef4444',
            borderVisible: false,
            wickUpColor: '#22c55e',
            wickDownColor: '#ef4444',
        });

        // Mock Data Generator
        const generateData = () => {
            const data = [];
            let time = new Date('2024-01-01').getTime() / 1000;
            let price = 100;
            for (let i = 0; i < 100; i++) {
                const volatility = 2;
                const open = price;
                const close = open + (Math.random() - 0.5) * volatility;
                const high = Math.max(open, close) + Math.random() * volatility;
                const low = Math.min(open, close) - Math.random() * volatility;

                data.push({
                    time: time as Time,
                    open,
                    high,
                    low,
                    close,
                });

                price = close;
                time += 86400;
            }
            return data;
        };

        candleSeries.setData(generateData());
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
            chart.remove();
        };
    }, []);

    return (
        <div className="glass-card p-6 rounded-xl border border-white/10 mb-6">
            <div className="flex items-center justify-between mb-4">
                <h3 className="text-xl font-bold text-white flex items-center gap-2">
                    <span className="w-2 h-2 bg-green-500 rounded-full animate-pulse" />
                    {t.chart.title}
                </h3>
                <div className="flex gap-2">
                    {(['24H', '1W', '1M'] as const).map(tf => (
                        <button key={tf} className="px-3 py-1 bg-white/5 hover:bg-white/10 rounded text-xs text-gray-400">
                            {t.chart.timeframes[tf]}
                        </button>
                    ))}
                </div>
            </div>
            <div ref={chartContainerRef} className="w-full h-[400px]" />
        </div>
    );
}
