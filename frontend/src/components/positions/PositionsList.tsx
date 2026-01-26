'use client';

import { useAccount, useReadContract } from 'wagmi';
import { POSITION_NFT_ABI } from '@/config/contracts';
import { PositionCard } from './PositionCard';

const POSITION_NFT_ADDRESS = '0x...' as `0x${string}`;

export function PositionsList() {
  const { address } = useAccount();

  const { data: positionsData } = useReadContract({
    address: POSITION_NFT_ADDRESS,
    abi: POSITION_NFT_ABI,
    functionName: 'getPositionsByOwner',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
      refetchInterval: 10000, // Refetch every 10 seconds
    },
  });

  const tokenIds = positionsData?.[0] || [];
  const positions = positionsData?.[1] || [];

  if (!address) {
    return null;
  }

  return (
    <div className="card">
      <h2 className="text-2xl font-bold mb-6">Your Positions</h2>

      {positions.length === 0 ? (
        <div className="text-center py-12 text-gray-400">
          <p className="text-lg mb-2">No open positions</p>
          <p className="text-sm">Open your first position above to get started</p>
        </div>
      ) : (
        <div className="space-y-4">
          {positions.map((position, index) => (
            <PositionCard
              key={tokenIds[index].toString()}
              tokenId={tokenIds[index]}
              position={position}
            />
          ))}
        </div>
      )}
    </div>
  );
}
