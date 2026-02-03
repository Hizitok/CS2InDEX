import './globals.css';
import type { Metadata } from 'next';
import { Providers } from './providers';
import { Header } from '@/components/layout/Header';
import { Toaster } from 'react-hot-toast';

export const metadata: Metadata = {
  title: 'CS2InDEX - Decentralized CS2 Item Perpetual Trading',
  description: 'Trade CS2 item perpetual contracts with up to 6x leverage',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="antialiased font-sans">
        <Providers>
          <div className="min-h-screen">
            <Header />
            <main>
              {children}
            </main>
            <Toaster
              position="bottom-right"
              toastOptions={{
                duration: 4000,
                style: {
                  background: '#1f2937',
                  color: '#fff',
                },
              }}
            />
          </div>
        </Providers>
      </body>
    </html>
  );
}
