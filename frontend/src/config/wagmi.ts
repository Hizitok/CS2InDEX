import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { sepolia, mainnet, localhost } from 'wagmi/chains';
import type { Chain } from 'wagmi/chains';

// Unichain Sepolia (chainId 1301) — not yet in wagmi/chains bundle
const unichainSepoliaRpc =
  process.env.NEXT_PUBLIC_UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';

const unichainSepolia: Chain = {
  id: 1301,
  name: 'Unichain Sepolia',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: {
    default: { http: [unichainSepoliaRpc] },
  },
  blockExplorers: {
    default: { name: 'Uniscan', url: 'https://sepolia.uniscan.xyz' },
  },
  testnet: true,
};

const isDev = process.env.NODE_ENV === 'development';

export const config = getDefaultConfig({
  appName: 'CS2InDEX',
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || 'YOUR_PROJECT_ID',
  // unichain-sepolia first so it's the default; localhost only in dev
  chains: isDev
    ? [unichainSepolia, localhost, sepolia, mainnet]
    : [unichainSepolia, sepolia, mainnet],
  ssr: true,
});
