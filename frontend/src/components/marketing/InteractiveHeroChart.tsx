'use client';

import { motion } from 'framer-motion';
import { useMemo } from 'react';

export function InteractiveHeroChart() {
    // Generate random candle data
    const candles = useMemo(() => {
        return Array.from({ length: 15 }).map((_, i) => { // Reduced count to 15 for better centering
            const isGreen = Math.random() > 0.45;
            // Constrain height to max 80% (20% base + 60% random)
            const height = 15 + Math.random() * 55;
            // Center vertical position more safely
            const yStart = 20 + Math.random() * 40;

            return {
                id: i,
                isGreen,
                height,
                yStart,
                wickTop: Math.random() * 10,
                wickBottom: Math.random() * 10,
            };
        });
    }, []);

    return (
        <div className="w-full h-[500px] flex items-center justify-center relative perspective-1000 overflow-hidden">
            {/* Chart Container - Changed to justify-center and gap-4 for true centering */}
            <div className="w-full h-[300px] flex items-center justify-center gap-4 px-4">
                {candles.map((candle) => (
                    <Candle key={candle.id} data={candle} />
                ))}
            </div>
            {/* Price card removed */}
        </div>
    );
}

function Candle({ data }: { data: any }) {
    // Softer colors and rounded shapes to match the frame
    const colorClass = data.isGreen ? 'bg-green-500/80 shadow-[0_0_10px_rgba(34,197,94,0.3)]' : 'bg-red-500/80 shadow-[0_0_10px_rgba(239,68,68,0.3)]';
    const wickColorClass = data.isGreen ? 'bg-green-500/60' : 'bg-red-500/60';

    return (
        <motion.div
            className="relative w-full h-full flex flex-col items-center justify-center group cursor-pointer"
            initial={{ opacity: 0, scaleY: 0 }}
            animate={{ opacity: 1, scaleY: 1 }}
            transition={{ delay: data.id * 0.05, duration: 0.5 }}
            whileHover={{
                scale: 1.15, // Reduced scale to prevent extreme overflow
                zIndex: 50,
                transition: { type: "spring", stiffness: 300 }
            }}
        >
            {/* Wick */}
            <div
                className={`w-[2px] absolute ${wickColorClass} rounded-full`}
                style={{
                    height: `${data.height + data.wickTop + data.wickBottom}%`,
                    bottom: `${data.yStart - data.wickBottom}%`
                }}
            />

            {/* Body - Rounded corners */}
            <div
                className={`w-3 md:w-4 rounded-md ${colorClass} relative z-10 transition-colors duration-300 backdrop-blur-sm`}
                style={{
                    height: `${data.height}%`,
                    marginBottom: `${data.yStart - 50}%` // Offset logic
                }}
            />
        </motion.div>
    );
}
