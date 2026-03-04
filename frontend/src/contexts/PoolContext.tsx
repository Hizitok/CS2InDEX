'use client';

import { createContext, useContext, useState, useMemo } from 'react';
import { useReadContract, useReadContracts } from 'wagmi';
import { FACTORY_ABI, CONTRACTS } from '@/config/contracts';

export interface PoolInfo {
  address: `0x${string}`;
  name: string;
}

interface PoolContextValue {
  pools: PoolInfo[];
  selectedPool: PoolInfo | null;
  setSelectedPool: (pool: PoolInfo) => void;
  isLoading: boolean;
}

const PoolContext = createContext<PoolContextValue>({
  pools: [],
  selectedPool: null,
  setSelectedPool: () => {},
  isLoading: true,
});

const FACTORY_IS_ZERO =
  CONTRACTS.FACTORY === '0x0000000000000000000000000000000000000000';

export function PoolProvider({ children }: { children: React.ReactNode }) {
  const [selectedAddress, setSelectedAddress] = useState<`0x${string}` | null>(null);

  // 1. Fetch all pool addresses from Factory
  const { data: poolAddresses, isLoading: loadingAddresses } = useReadContract({
    address: CONTRACTS.FACTORY,
    abi: FACTORY_ABI,
    functionName: 'getAllPools',
    query: { enabled: !FACTORY_IS_ZERO },
  });

  // 2. Batch-fetch pool info (name) for each address
  const contracts = useMemo(() => {
    if (!poolAddresses) return [];
    return poolAddresses.map((addr) => ({
      address: CONTRACTS.FACTORY as `0x${string}`,
      abi: FACTORY_ABI,
      functionName: 'getPoolInfo' as const,
      args: [addr] as [`0x${string}`],
    }));
  }, [poolAddresses]);

  const { data: poolInfos, isLoading: loadingInfos } = useReadContracts({
    contracts,
    query: { enabled: contracts.length > 0 },
  });

  // 3. Build typed pool list
  const pools = useMemo<PoolInfo[]>(() => {
    if (!poolAddresses) return [];
    return poolAddresses.map((addr, i) => {
      const result = poolInfos?.[i]?.result as { itemName?: string } | undefined;
      return {
        address: addr,
        name: result?.itemName ?? `Pool ${i + 1}`,
      };
    });
  }, [poolAddresses, poolInfos]);

  // 4. Selected pool — auto-default to first pool
  const selectedPool = useMemo<PoolInfo | null>(() => {
    if (pools.length === 0) return null;
    return pools.find((p) => p.address === selectedAddress) ?? pools[0];
  }, [pools, selectedAddress]);

  const setSelectedPool = (pool: PoolInfo) => setSelectedAddress(pool.address);

  return (
    <PoolContext.Provider
      value={{
        pools,
        selectedPool,
        setSelectedPool,
        isLoading: loadingAddresses || loadingInfos,
      }}
    >
      {children}
    </PoolContext.Provider>
  );
}

export const usePool = () => useContext(PoolContext);
