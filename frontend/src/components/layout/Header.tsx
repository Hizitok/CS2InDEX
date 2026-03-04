'use client';

import { useState, useRef, useEffect } from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import Link from 'next/link';
import { TrendingUp, Globe, ChevronDown, Check } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { usePool } from '@/contexts/PoolContext';

export function Header() {
  const { t, language, toggleLanguage } = useLanguage();
  const { pools, selectedPool, setSelectedPool } = usePool();
  const [open, setOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClick = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

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

          <div className="flex items-center gap-3">
            {/* Pool Selector */}
            {selectedPool && (
              <div className="relative" ref={dropdownRef}>
                <button
                  onClick={() => pools.length > 1 && setOpen((v) => !v)}
                  className={`flex items-center gap-2 px-3 py-2 rounded-lg text-sm border border-white/10 transition-colors ${
                    pools.length > 1
                      ? 'bg-white/5 hover:bg-white/10 text-gray-300 hover:text-white cursor-pointer'
                      : 'bg-white/5 text-gray-400 cursor-default'
                  }`}
                  title={selectedPool.address}
                >
                  <span className="max-w-[150px] truncate font-medium">{selectedPool.name}</span>
                  {pools.length > 1 && (
                    <ChevronDown
                      size={14}
                      className={`flex-shrink-0 text-gray-500 transition-transform ${open ? 'rotate-180' : ''}`}
                    />
                  )}
                </button>

                {open && pools.length > 1 && (
                  <div className="absolute top-full mt-2 right-0 min-w-[220px] bg-[#0f0f0f] border border-white/10 rounded-xl shadow-2xl z-50 overflow-hidden">
                    <div className="px-3 py-2 border-b border-white/5">
                      <p className="text-[11px] text-gray-500 uppercase tracking-wider">Select Pool</p>
                    </div>
                    {pools.map((pool) => {
                      const isSelected = selectedPool.address === pool.address;
                      return (
                        <button
                          key={pool.address}
                          onClick={() => { setSelectedPool(pool); setOpen(false); }}
                          className={`w-full flex items-center justify-between px-4 py-3 text-left text-sm transition-colors hover:bg-white/5 ${
                            isSelected ? 'text-accent-cyan' : 'text-gray-300'
                          }`}
                        >
                          <span>{pool.name}</span>
                          {isSelected && <Check size={14} className="flex-shrink-0" />}
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>
            )}

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
