'use client';

import { Activity, ShieldCheck, TrendingDown } from 'lucide-react';
import Link from 'next/link';
import { useLanguage } from '@/contexts/LanguageContext';
import { motion } from 'framer-motion';
import { InteractiveHeroChart } from '@/components/marketing/InteractiveHeroChart';

export default function Home() {
  const { t } = useLanguage();

  return (
    <main className="h-screen w-full overflow-y-scroll snap-y snap-mandatory bg-bedrock-950 scroll-smooth">

      {/* SECTION 1: HERO */}
      <section className="h-screen w-full snap-start flex flex-col justify-center relative overflow-hidden px-4 md:px-12 bg-black">
        {/* Background Glow */}
        <div className="absolute top-1/2 right-0 -translate-y-1/2 w-[600px] h-[600px] bg-accent-purple/10 rounded-full blur-[150px] -z-10 pointer-events-none" />

        {/* CS2 Decorative Elements */}
        {/* CS2 Decorative Watermarks (Adaptive & Negative Effect) */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 2 }}
          className="absolute top-0 left-0 w-full h-full pointer-events-none z-0 overflow-hidden"
        >
          {/* Left Watermark (AK47 Silhouette) */}
          <img
            src="/cs2-elements.png"
            alt="CS2 Decor"
            className="absolute top-[10%] -left-[10%] w-[50vw] max-w-[800px] opacity-[0.15] invert rotate-[-15deg] select-none blur-[2px]"
          />
          {/* Right Watermark (Karambit Silhouette) */}
          <img
            src="/cs2-elements.png"
            alt="CS2 Decor"
            className="absolute bottom-[5%] -right-[5%] w-[45vw] max-w-[700px] opacity-[0.15] invert rotate-[15deg] select-none blur-[2px]"
          />
        </motion.div>

        <div className="container mx-auto grid grid-cols-1 lg:grid-cols-2 gap-12 items-center h-full">
          {/* Left Column: Text & CTA */}
          <div className="text-left space-y-8 z-10">
            <motion.h1
              initial={{ opacity: 0, x: -20 }}
              whileInView={{ opacity: 1, x: 0 }}
              transition={{ duration: 0.8 }}
              className="text-6xl md:text-8xl font-bold tracking-tighter text-white leading-[1.1]"
            >
              {t.hero.title}
            </motion.h1>

            <motion.p
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              transition={{ delay: 0.2, duration: 0.8 }}
              className="text-xl text-gray-400 max-w-lg leading-relaxed"
            >
              {t.hero.subtitle}
            </motion.p>

            <motion.div
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.4, duration: 0.5 }}
              className="flex flex-wrap gap-4"
            >
              <Link href="/positions" className="px-10 py-4 bg-white text-black rounded-full font-bold text-lg hover:scale-105 transition-transform">
                {t.hero.launchApp}
              </Link>
              <Link href="/docs" className="px-10 py-4 bg-transparent border border-gray-700 hover:border-white text-white rounded-full font-bold text-lg transition-colors">
                {t.hero.readDocs}
              </Link>
            </motion.div>

            {/* Trusted By / Partner Strip */}
            <motion.div
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              transition={{ delay: 0.8 }}
              className="pt-12"
            >
              <p className="text-sm text-gray-600 mb-4 uppercase tracking-widest">Powered By</p>
              <div className="flex gap-8 opacity-50 grayscale hover:grayscale-0 transition-all duration-500">
                {/* Simple typographic logos for now */}
                <div className="text-2xl font-bold font-mono text-gray-400">ETHEREUM</div>
                <div className="text-2xl font-bold font-mono text-gray-400">CHAINLINK</div>
                <div className="text-2xl font-bold font-mono text-gray-400">THE GRAPH</div>
              </div>
            </motion.div>
          </div>

          {/* Right Column: Interactive Chart (Browser Window Style) */}
          <div className="relative hidden lg:flex h-full items-center justify-center">
            <motion.div
              initial={{ opacity: 0, x: 50 }}
              whileInView={{ opacity: 1, x: 0 }}
              transition={{ duration: 1, delay: 0.2 }}
              className="w-full max-w-[600px] perspective-1000"
            >
              {/* Browser Frame */}
              <div className="rounded-xl border border-white/10 bg-[#0a0a0a]/80 backdrop-blur-md shadow-2xl overflow-hidden transform rotate-y-[-5deg] rotate-x-[5deg] transition-transform hover:rotate-0 duration-500">
                {/* Header Bar */}
                <div className="h-10 bg-white/5 border-b border-white/5 flex items-center px-4 gap-2">
                  <div className="flex gap-2">
                    <div className="w-3 h-3 rounded-full bg-red-500/20" />
                    <div className="w-3 h-3 rounded-full bg-yellow-500/20" />
                    <div className="w-3 h-3 rounded-full bg-green-500/20" />
                  </div>
                  {/* Addr Bar Mockup */}
                  <div className="ml-4 flex-1 h-6 bg-black/40 rounded flex items-center px-3 text-[10px] text-gray-600 font-mono">
                    cs2index.io/trade
                  </div>
                </div>

                {/* Chart Body */}
                <div className="p-1 relative">
                  <div className="absolute inset-0 bg-gradient-to-b from-accent-cyan/5 to-transparent pointer-events-none" />
                  <InteractiveHeroChart />
                </div>
              </div>
            </motion.div>
          </div>
        </div>

        {/* Scroll Indicator */}
        <motion.div
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 1, duration: 1 }}
          className="absolute bottom-10 left-1/2 -translate-x-1/2 flex flex-col items-center gap-2 pointer-events-none"
        >
          <span className="text-[10px] uppercase tracking-widest text-gray-500 font-bold">Scroll</span>
          <motion.div
            animate={{ y: [0, 8, 0] }}
            transition={{ duration: 1.5, repeat: Infinity, ease: "easeInOut" }}
            className="w-[1px] h-12 bg-gradient-to-b from-transparent via-accent-cyan/50 to-accent-cyan"
          />
        </motion.div>
      </section>


      {/* SECTION 2: INNOVATION (Index Trading) */}
      <section className="h-screen w-full snap-start flex items-center relative overflow-hidden px-4 bg-bedrock-900/50">
        <div className="container mx-auto grid grid-cols-1 md:grid-cols-2 gap-16 items-center">
          <div className="order-2 md:order-1">
            <motion.div
              initial={{ scale: 0.8, opacity: 0 }}
              whileInView={{ scale: 1, opacity: 1 }}
              transition={{ duration: 0.8 }}
              className="relative"
            >
              <div className="absolute inset-0 bg-accent-cyan/20 blur-[80px] rounded-full" />
              <div className="relative glass-card p-10 rounded-3xl border border-accent-cyan/30">
                <Activity size={120} className="text-accent-cyan mx-auto mb-6" />
                <div className="text-center font-mono text-accent-cyan/80">CS2 Market Index Analysis</div>
              </div>
            </motion.div>
          </div>

          <div className="order-1 md:order-2 text-left">
            <h2 className="text-5xl font-bold mb-6 text-white leading-tight">
              {t.marketing.innovationTitle}
            </h2>
            <p className="text-xl text-gray-400 mb-8 leading-relaxed">
              {t.marketing.innovationDesc}
            </p>
            <ul className="space-y-4">
              {['Top 100 Liquid Skins', 'Algorithmic Weighting', 'Real-time Rebalancing'].map((item, i) => (
                <li key={i} className="flex items-center gap-3 text-lg text-gray-300">
                  <div className="w-2 h-2 bg-accent-cyan rounded-full" /> {item}
                </li>
              ))}
            </ul>
          </div>
        </div>
      </section>


      {/* SECTION 3: UTILITY (Hedging) */}
      <section className="h-screen w-full snap-start flex items-center relative overflow-hidden px-4">
        {/* Background Gradient */}
        <div className="absolute right-0 top-0 w-[50%] h-full bg-gradient-to-l from-red-900/10 to-transparent -z-10" />

        <div className="container mx-auto grid grid-cols-1 md:grid-cols-2 gap-16 items-center">
          <div className="text-left">
            <h2 className="text-5xl font-bold mb-6 text-white leading-tight">
              {t.marketing.hedgingTitle}
            </h2>
            <p className="text-xl text-gray-400 mb-8 leading-relaxed">
              {t.marketing.hedgingDesc}
            </p>

            <div className="flex gap-4">
              <div className="glass-card p-4 rounded-xl flex items-center gap-3 border-red-500/30">
                <TrendingDown className="text-red-500" />
                <span className="font-bold text-red-400">Inventory Value Drops</span>
              </div>
              <div className="text-2xl text-gray-500 flex items-center">+</div>
              <div className="glass-card p-4 rounded-xl flex items-center gap-3 border-green-500/30">
                <ShieldCheck className="text-green-500" />
                <span className="font-bold text-green-400">Short Position Profits</span>
              </div>
            </div>
          </div>

          <div>
            <motion.div
              initial={{ x: 100, opacity: 0 }}
              whileInView={{ x: 0, opacity: 1 }}
              transition={{ duration: 0.8 }}
              className="relative"
            >
              <div className="absolute inset-0 bg-red-500/10 blur-[80px] rounded-full" />
              <div className="relative glass-card p-8 rounded-3xl border border-white/10">
                {/* Simplified Chart Visual */}
                <div className="h-64 flex items-end gap-2 px-4 pb-4 border-b border-gray-700">
                  {[40, 60, 55, 70, 45, 30, 20].map((h, i) => (
                    <div key={i} className={`flex-1 rounded-t-sm ${i > 3 ? 'bg-red-500' : 'bg-gray-600'}`} style={{ height: `${h}%` }} />
                  ))}
                </div>
                <div className="mt-4 flex justify-between text-sm">
                  <span className="text-red-400 font-bold">Market Crash</span>
                  <span className="text-green-400 font-bold">Portfolio Protected</span>
                </div>
              </div>
            </motion.div>
          </div>
        </div>

        {/* Footer in the last section */}
        <div className="absolute bottom-4 left-0 right-0 text-center text-gray-600 text-sm">
          {t.footer.rights}
        </div>
      </section>

    </main>
  );
}
