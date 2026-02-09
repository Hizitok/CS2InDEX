'use client';

import { motion } from 'framer-motion';
import { useLanguage } from '@/contexts/LanguageContext';

export function ArchitectureDiagram() {
    const { t } = useLanguage();

    const nodes = [
        { id: 'user', label: t.docs.arch.user, x: '50%', y: '10%', color: 'bg-blue-500' },
        { id: 'frontend', label: t.docs.arch.frontend, x: '50%', y: '30%', color: 'bg-indigo-500' },
        { id: 'vault', label: t.docs.arch.vault, x: '25%', y: '60%', color: 'bg-green-500' },
        { id: 'pool', label: t.docs.arch.pool, x: '50%', y: '60%', color: 'bg-purple-600' },
        { id: 'oracle', label: t.docs.arch.oracle, x: '75%', y: '60%', color: 'bg-orange-500' },
    ];

    return (
        <div className="glass-card p-8 rounded-2xl border border-white/10 my-12">
            <h3 className="text-2xl font-bold mb-8 text-white">{t.docs.archTitle}</h3>

            <div className="relative h-[400px] bg-bedrock-900/30 rounded-xl border border-white/5 overflow-hidden">
                {/* Connection Lines (simplified visual representation) */}
                <svg className="absolute inset-0 w-full h-full pointer-events-none opacity-30">
                    <line x1="50%" y1="15%" x2="50%" y2="25%" stroke="white" strokeWidth="2" strokeDasharray="5,5" />
                    <line x1="50%" y1="35%" x2="25%" y2="55%" stroke="white" strokeWidth="2" />
                    <line x1="50%" y1="35%" x2="50%" y2="55%" stroke="white" strokeWidth="2" />
                    <line x1="50%" y1="35%" x2="75%" y2="55%" stroke="white" strokeWidth="2" />
                </svg>

                {nodes.map((node) => (
                    <motion.div
                        key={node.id}
                        className={`absolute px-6 py-3 rounded-lg shadow-lg text-white font-bold cursor-help backdrop-blur-md border border-white/20 ${node.color}`}
                        style={{
                            left: node.x,
                            top: node.y,
                            translateX: '-50%',
                            translateY: '-50%'
                        }}
                        whileHover={{ scale: 1.1, zIndex: 10 }}
                    >
                        {node.label}
                    </motion.div>
                ))}

                <div className="absolute bottom-4 left-0 right-0 text-center text-xs text-gray-500">
                    * Hover nodes to interact (Coming Soon)
                </div>
            </div>
        </div>
    );
}
