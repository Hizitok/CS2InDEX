import { useReadContract } from 'wagmi';
import { formatUnits } from 'viem';
import { POOL_ABI, PX_DECIMALS } from '@/config/contracts';

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

export type DepthLevel = { price: number; size: number; cumSize: number };

export function useDepth(poolAddress?: `0x${string}`, nLevels = 20) {
    const { data, isLoading, refetch } = useReadContract({
        address: poolAddress,
        abi: POOL_ABI,
        functionName: 'getDepth',
        args: [BigInt(nLevels)],
        query: {
            enabled: !!poolAddress,
            refetchInterval: 3000,
        },
    });

    const scale = 10 ** PX_DECIMALS;

    const toLevel = (prices: readonly bigint[], sizes: readonly bigint[]): DepthLevel[] => {
        let cum = 0;
        return prices
            .map((p, i) => ({ price: Number(p) / scale, size: Number(sizes[i]) / scale }))
            .filter(l => l.price > 0)
            .map(l => { cum += l.size; return { ...l, cumSize: cum }; });
    };

    const [askPrices, askSizes, bidPrices, bidSizes] = (data ?? [[], [], [], []]) as [
        readonly bigint[], readonly bigint[], readonly bigint[], readonly bigint[]
    ];

    return {
        asks: toLevel(askPrices, askSizes),   // ascending price
        bids: toLevel(bidPrices, bidSizes),   // descending price
        isLoading,
        refetch,
    };
}
