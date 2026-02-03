'use client';

import { useLanguage } from '@/contexts/LanguageContext';
import { InteractiveWorkflow } from '@/components/docs/InteractiveWorkflow';

export default function DocsPage() {
    const { t } = useLanguage();

    return (
        <div className="container mx-auto px-4 pt-24 pb-20 relative min-h-screen">
            {/* Background Glow */}
            <div className="absolute top-0 right-0 w-[500px] h-[500px] bg-accent-purple/10 rounded-full blur-[100px] -z-10 pointer-events-none" />

            <div className="max-w-5xl mx-auto">
                <div className="glass-card p-10 rounded-3xl prose prose-invert max-w-none prose-headings:text-transparent prose-headings:bg-clip-text prose-headings:bg-gradient-to-r prose-headings:from-white prose-headings:to-gray-300 prose-a:text-accent-cyan hover:prose-a:text-accent-purple mb-12">
                    <h1 className="!text-4xl font-bold mb-8">{t.nav.docs}</h1>

                    <div className="mb-12">
                        <p className="lead text-xl text-gray-300">
                            {t.hero.subtitle}
                        </p>
                    </div>

                    <InteractiveWorkflow />

                </div>
            </div>
        </div>
    );
}
