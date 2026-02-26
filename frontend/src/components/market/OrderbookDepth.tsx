'use client';

import { useMemo } from 'react';
import { useDepth, DepthLevel } from '@/hooks/usePool';

interface Props {
    poolAddress?: `0x${string}`;
    /** Mock data for demo when no pool is connected */
    demo?: boolean;
}

// ── Mock data for offline demo ────────────────────────────────────────────────
function mockLevels(side: 'ask' | 'bid', midPrice = 100, n = 12): DepthLevel[] {
    const step = 0.5;
    let cum = 0;
    return Array.from({ length: n }, (_, i) => {
        const price = side === 'ask'
            ? midPrice + step * (i + 1)
            : midPrice - step * (i + 1);
        const size = Math.round((15 - i * 0.8 + Math.random() * 4) * 10) / 10;
        cum += size;
        return { price, size, cumSize: cum };
    });
}

// ── SVG Depth Chart ───────────────────────────────────────────────────────────
function DepthSVG({ asks, bids }: { asks: DepthLevel[]; bids: DepthLevel[] }) {
    const W = 600;
    const H = 200;
    const PAD = { top: 12, bottom: 28, left: 8, right: 8 };

    const chartW = W - PAD.left - PAD.right;
    const chartH = H - PAD.top - PAD.bottom;

    const allPrices = [...bids.map(l => l.price), ...asks.map(l => l.price)];
    const allCum = [...bids.map(l => l.cumSize), ...asks.map(l => l.cumSize)];

    if (allPrices.length === 0) {
        return (
            <div className="flex items-center justify-center h-[200px] text-gray-600 text-sm font-mono">
                No orders in book
            </div>
        );
    }

    const minPx = Math.min(...allPrices);
    const maxPx = Math.max(...allPrices);
    const maxCum = Math.max(...allCum, 1);

    const xScale = (price: number) =>
        PAD.left + ((price - minPx) / (maxPx - minPx || 1)) * chartW;
    const yScale = (cum: number) =>
        PAD.top + chartH - (cum / maxCum) * chartH;

    const buildPath = (levels: DepthLevel[], side: 'bid' | 'ask'): string => {
        if (levels.length === 0) return '';
        const pts: [number, number][] = [];
        const baseline = PAD.top + chartH;

        if (side === 'bid') {
            // Start at bottom-right of bid area
            const firstX = xScale(levels[0].price);
            pts.push([firstX, baseline]);
            for (const l of levels) {
                const x = xScale(l.price);
                const y = yScale(l.cumSize);
                pts.push([x, y]);
            }
            // Close to bottom-left
            pts.push([xScale(levels[levels.length - 1].price), baseline]);
        } else {
            // Start at bottom-left of ask area
            const firstX = xScale(levels[0].price);
            pts.push([firstX, baseline]);
            for (const l of levels) {
                const x = xScale(l.price);
                const y = yScale(l.cumSize);
                pts.push([x, y]);
            }
            // Close to bottom-right
            pts.push([xScale(levels[levels.length - 1].price), baseline]);
        }

        return pts.map(([x, y], i) => `${i === 0 ? 'M' : 'L'}${x.toFixed(1)},${y.toFixed(1)}`).join(' ') + ' Z';
    };

    // Price tick labels (5 evenly spaced)
    const ticks = Array.from({ length: 5 }, (_, i) =>
        minPx + (maxPx - minPx) * (i / 4)
    );

    return (
        <svg viewBox={`0 0 ${W} ${H}`} className="w-full" style={{ height: H }}>
            {/* Grid lines */}
            {[0.25, 0.5, 0.75, 1].map(f => (
                <line
                    key={f}
                    x1={PAD.left} x2={W - PAD.right}
                    y1={PAD.top + chartH * (1 - f)} y2={PAD.top + chartH * (1 - f)}
                    stroke="rgba(255,255,255,0.05)" strokeWidth="1"
                />
            ))}

            {/* Bid area (green) */}
            <path d={buildPath(bids, 'bid')} fill="rgba(34,197,94,0.15)" stroke="#22c55e" strokeWidth="1.5" />
            {/* Ask area (red) */}
            <path d={buildPath(asks, 'ask')} fill="rgba(239,68,68,0.15)" stroke="#ef4444" strokeWidth="1.5" />

            {/* Mid-price line */}
            {bids[0] && asks[0] && (() => {
                const midX = xScale((bids[0].price + asks[0].price) / 2);
                return (
                    <line
                        x1={midX} x2={midX}
                        y1={PAD.top} y2={PAD.top + chartH}
                        stroke="rgba(148,163,184,0.4)" strokeWidth="1" strokeDasharray="4,4"
                    />
                );
            })()}

            {/* Price axis labels */}
            {ticks.map((px, i) => (
                <text
                    key={i}
                    x={xScale(px)} y={H - 4}
                    textAnchor="middle" fontSize="9" fill="#6b7280"
                    fontFamily="monospace"
                >
                    {px.toFixed(2)}
                </text>
            ))}
        </svg>
    );
}

// ── Orderbook Table (right panel) ─────────────────────────────────────────────
function BookTable({ asks, bids }: { asks: DepthLevel[]; bids: DepthLevel[] }) {
    const spread = asks[0] && bids[0] ? (asks[0].price - bids[0].price).toFixed(2) : '—';

    return (
        <div className="font-mono text-xs flex flex-col h-full">
            {/* Header */}
            <div className="grid grid-cols-3 text-gray-500 pb-1 border-b border-white/5 mb-1">
                <span>Price</span>
                <span className="text-right">Size</span>
                <span className="text-right">Total</span>
            </div>

            {/* Asks (reversed — lowest ask at bottom nearest to spread) */}
            <div className="flex-1 overflow-hidden">
                {[...asks].reverse().slice(0, 8).reverse().map((l, i) => (
                    <div key={i} className="grid grid-cols-3 text-red-400 leading-5 relative">
                        <span className="z-10">{l.price.toFixed(2)}</span>
                        <span className="text-right z-10">{l.size.toFixed(2)}</span>
                        <span className="text-right z-10 text-gray-500">{l.cumSize.toFixed(2)}</span>
                        {/* Volume bar */}
                        <div
                            className="absolute right-0 top-0 h-full bg-red-500/10"
                            style={{ width: `${(l.cumSize / (asks[asks.length - 1]?.cumSize || 1)) * 100}%` }}
                        />
                    </div>
                ))}
            </div>

            {/* Spread */}
            <div className="text-center py-1 text-gray-500 border-y border-white/5 my-1">
                Spread: <span className="text-white">{spread}</span>
            </div>

            {/* Bids */}
            <div className="flex-1 overflow-hidden">
                {bids.slice(0, 8).map((l, i) => (
                    <div key={i} className="grid grid-cols-3 text-green-400 leading-5 relative">
                        <span className="z-10">{l.price.toFixed(2)}</span>
                        <span className="text-right z-10">{l.size.toFixed(2)}</span>
                        <span className="text-right z-10 text-gray-500">{l.cumSize.toFixed(2)}</span>
                        <div
                            className="absolute right-0 top-0 h-full bg-green-500/10"
                            style={{ width: `${(l.cumSize / (bids[bids.length - 1]?.cumSize || 1)) * 100}%` }}
                        />
                    </div>
                ))}
            </div>
        </div>
    );
}

// ── Main Export ───────────────────────────────────────────────────────────────
export function OrderbookDepth({ poolAddress, demo = false }: Props) {
    const live = useDepth(poolAddress, 20);

    const asks = useMemo(
        () => (demo || live.asks.length === 0 ? mockLevels('ask') : live.asks),
        [demo, live.asks]
    );
    const bids = useMemo(
        () => (demo || live.bids.length === 0 ? mockLevels('bid') : live.bids),
        [demo, live.bids]
    );

    const isDemoMode = demo || (live.asks.length === 0 && live.bids.length === 0);

    return (
        <div className="glass-card rounded-xl border border-white/10 p-4 mb-6">
            {/* Title bar */}
            <div className="flex items-center justify-between mb-3">
                <h3 className="text-base font-bold text-white flex items-center gap-2">
                    <span className="w-2 h-2 rounded-full bg-accent-cyan animate-pulse" />
                    Order Book Depth
                </h3>
                {isDemoMode && (
                    <span className="text-[10px] text-yellow-500/70 font-mono border border-yellow-500/30 px-2 py-0.5 rounded">
                        DEMO
                    </span>
                )}
                {!isDemoMode && live.isLoading && (
                    <span className="text-[10px] text-gray-500 font-mono">loading…</span>
                )}
            </div>

            {/* Layout: chart left + table right */}
            <div className="grid grid-cols-1 md:grid-cols-[1fr_180px] gap-4">
                <DepthSVG asks={asks} bids={bids} />
                <BookTable asks={asks} bids={bids} />
            </div>
        </div>
    );
}
