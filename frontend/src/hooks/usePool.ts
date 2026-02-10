import { useReadContract } from 'wagmi';
import { POOL_ABI } from '@/config/contracts';

export function useOrderbook(poolAddress?: `0x${string}`) {
    const { data, isLoading, refetch } = useReadContract({
        address: poolAddress,
        abi: POOL_ABI,
        functionName: 'getOrderbookInfo',
        query: {
            enabled: !!poolAddress,
        }
    });

    return {
        lastPrice: (data as any)?.[0],
        askPrice: (data as any)?.[1],
        bidPrice: (data as any)?.[2],
        isLoading,
        refetch
    };
}

export function useLastPrice(poolAddress?: `0x${string}`) {
    const { data } = useReadContract({
        address: poolAddress,
        abi: POOL_ABI,
        functionName: 'getLastPrice',
        query: {
            enabled: !!poolAddress,
        }
    });

    return {
        price: data,
    };
}

export function useFundingRate(poolAddress?: `0x${string}`) {
    const { data } = useReadContract({
        address: poolAddress,
        abi: POOL_ABI,
        functionName: 'fundingIdx',
        query: {
            enabled: !!poolAddress,
        }
    });

    return {
        fundingIdx: data,
    };
}
