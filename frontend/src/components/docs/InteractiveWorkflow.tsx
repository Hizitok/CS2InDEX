'use client';

import { useState } from 'react';
import { motion } from 'framer-motion';
import { Wallet, PiggyBank, TrendingUp, ShieldCheck } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';

export function InteractiveWorkflow() {
    const { t } = useLanguage();
    const [activeStep, setActiveStep] = useState(0);

    const steps = [
        {
            id: 'connect',
            icon: <Wallet size={24} />,
            title: t.docs.steps.connect,
            desc: t.docs.steps.connectDesc,
            detail: t.docs.steps.connectDetail,
        },
        {
            id: 'deposit',
            icon: <PiggyBank size={24} />,
            title: t.docs.steps.deposit,
            desc: t.docs.steps.depositDesc,
            detail: t.docs.steps.depositDetail,
        },
        {
            id: 'trade',
            icon: <TrendingUp size={24} />,
            title: t.docs.steps.trade,
            desc: t.docs.steps.tradeDesc,
            detail: t.docs.steps.tradeDetail,
        },
        {
            id: 'manage',
            icon: <ShieldCheck size={24} />,
            title: t.docs.steps.manage,
            desc: t.docs.steps.manageDesc,
            detail: t.docs.steps.manageDetail,
        }
    ];

    return (
        <div className="glass-card p-8 rounded-2xl border border-white/10">
            <h3 className="text-2xl font-bold mb-8 text-white">{t.docs.workflowTitle}</h3>

            <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
                {/* Stepper Navigation */}
                <div className="lg:col-span-4 space-y-4">
                    {steps.map((step, idx) => (
                        <button
                            key={step.id}
                            onClick={() => setActiveStep(idx)}
                            className={`w-full text-left p-4 rounded-xl transition-all border ${activeStep === idx
                                    ? 'bg-bedrock-800 border-accent-cyan/50 shadow-lg shadow-accent-cyan/10'
                                    : 'bg-transparent border-transparent hover:bg-white/5'
                                }`}
                        >
                            <div className="flex items-center gap-3">
                                <div className={`p-2 rounded-lg ${activeStep === idx ? 'bg-accent-cyan text-black' : 'bg-gray-800 text-gray-400'}`}>
                                    {step.icon}
                                </div>
                                <div>
                                    <div className={`font-bold ${activeStep === idx ? 'text-white' : 'text-gray-400'}`}>
                                        {step.title}
                                    </div>
                                    <div className="text-xs text-gray-500 line-clamp-1">{step.desc}</div>
                                </div>
                            </div>
                        </button>
                    ))}
                </div>

                {/* Detail View */}
                <div className="lg:col-span-8">
                    <motion.div
                        key={activeStep}
                        initial={{ opacity: 0, x: 20 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{ duration: 0.3 }}
                        className="h-full bg-bedrock-900/50 rounded-2xl p-6 border border-white/5 relative overflow-hidden"
                    >
                        {/* Background Icon */}
                        <div className="absolute -bottom-10 -right-10 text-white/5 transform rotate-12">
                            {React.cloneElement(steps[activeStep].icon as React.ReactElement, { size: 200 })}
                        </div>

                        <h4 className="text-xl font-bold text-accent-cyan mb-4 flex items-center gap-2">
                            <span className="w-8 h-8 rounded-full bg-accent-cyan/20 flex items-center justify-center text-sm">
                                {activeStep + 1}
                            </span>
                            {steps[activeStep].title}
                        </h4>

                        <p className="text-gray-300 text-lg mb-6 leading-relaxed">
                            {steps[activeStep].detail}
                        </p>

                        <div className="bg-black/30 rounded-lg p-4 font-mono text-sm text-green-400 border border-white/5">
                            <div className="flex items-center gap-2 mb-2 text-xs text-gray-500 uppercase tracking-wider">
                                <span className="w-2 h-2 rounded-full bg-green-500 animate-pulse" />
                                Action
                            </div>
                            {'>'} {steps[activeStep].desc}
                        </div>
                    </motion.div>
                </div>
            </div>
        </div>
    );
}

import React from 'react';
