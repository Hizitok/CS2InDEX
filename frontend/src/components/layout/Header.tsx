'use client';

import { ConnectButton } from '@rainbow-me/rainbowkit';
import Link from 'next/link';
import { TrendingUp } from 'lucide-react';

export function Header() {
  return (
    <header className="border-b border-gray-800 bg-gray-900/50 backdrop-blur-sm sticky top-0 z-50">
      <div className="container mx-auto px-4">
        <div className="flex items-center justify-between h-16">
          {/* Logo */}
          <Link href="/" className="flex items-center gap-2 hover:opacity-80 transition-opacity">
            <TrendingUp className="text-primary-500" size={28} />
            <span className="text-xl font-bold bg-gradient-to-r from-primary-400 to-primary-600 bg-clip-text text-transparent">
              CS2InDEX
            </span>
          </Link>

          {/* Navigation */}
          <nav className="hidden md:flex items-center gap-6">
            <Link href="/" className="text-gray-300 hover:text-white transition-colors">
              Trade
            </Link>
            <Link href="/positions" className="text-gray-300 hover:text-white transition-colors">
              Positions
            </Link>
            <Link href="/markets" className="text-gray-300 hover:text-white transition-colors">
              Markets
            </Link>
            <Link href="/docs" className="text-gray-300 hover:text-white transition-colors">
              Docs
            </Link>
          </nav>

          {/* Connect Wallet */}
          <ConnectButton />
        </div>
      </div>
    </header>
  );
}
