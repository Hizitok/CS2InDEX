'use client';

import { ConnectButton } from '@rainbow-me/rainbowkit';
import Link from 'next/link';
import { TrendingUp, Globe } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';

export function Header() {
  const { t, language, toggleLanguage } = useLanguage();
  return (
    <header className="fixed top-0 w-full z-50 bg-bedrock-900/80 backdrop-blur-md border-b border-white/5">
      <div className="container mx-auto px-4">
        <div className="flex items-center justify-between h-20">
          {/* Logo */}
          <Link href="/" className="flex items-center gap-2 hover:opacity-80 transition-opacity">
            <TrendingUp className="text-accent-cyan" size={32} />
            <span className="text-2xl font-bold bg-gradient-to-r from-accent-purple to-accent-cyan bg-clip-text text-transparent">
              CS2InDEX
            </span>
          </Link>

          {/* Navigation */}
          <nav className="hidden md:flex items-center gap-6">
            <Link href="/positions" className="text-gray-300 hover:text-white transition-colors font-medium">
              {t.nav.trade}
            </Link>
            <Link href="/markets" className="text-gray-300 hover:text-white transition-colors font-medium">
              {t.nav.markets}
            </Link>
            <Link href="/docs" className="text-gray-300 hover:text-white transition-colors font-medium">
              {t.nav.docs}
            </Link>
          </nav>

          <div className="flex items-center gap-4">
            {/* Language Toggle */}
            <button
              onClick={toggleLanguage}
              className="p-2 rounded-full hover:bg-white/10 text-gray-400 hover:text-white transition-colors flex items-center gap-2"
              title={language === 'en' ? 'Switch to Chinese' : 'Switch to English'}
            >
              <Globe size={20} />
              <span className="text-sm font-bold uppercase">{language}</span>
            </button>

            {/* Connect Wallet */}
            <ConnectButton />
          </div>
        </div>
      </div>
    </header>
  );
}
