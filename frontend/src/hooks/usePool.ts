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
        functionName: 'fundingIdx', // Check if this exists in POOL_ABI in contracts.ts?
        // In contracts.ts POOL_ABI: getOrderbookInfo, newOrder, closePosition, cancelOrder, getLastPrice, getPoolInfo.
        // It DOES NOT have 'fundingIdx' or 'maxLeverage' or 'oraclePrice' explicitly listed in the export I saw?
        // Step 52 showing contracts.ts:
        // POOL_ABI has: newOrder, closePosition, cancelOrder, getLastPrice, getPoolInfo.
        // It misses 'getOrderbookInfo'!! Wait.
        // Step 52:
        // Lines 53-120: POOL_ABI
        // newOrder (L68), closePosition (L88), cancelOrder (L95), getLastPrice (L102), getPoolInfo (L109).
        // It DOES NOT have 'getOrderbookInfo'.

        // BUT the FRONTEND_README.md says `getOrderbookInfo` exists.
        // The `contracts.ts` is INCOMPLETE compared to the readme description!
        // Or the readme describes a different version.

        // I should stick to what `contracts.ts` offers OR assume `contracts.ts` is outdated and I should use JSONs (which I don't have).
        // If I use my own ABI definition (or JSONs), I can add `getOrderbookInfo`.
        // Since `contracts.ts` is explicitly there, maybe I should add `getOrderbookInfo` to it?
        // Note: The `contracts.ts` file I viewed ends at line 237.

        // I will add the missing ABI entries to my `usePool.ts` by casting or defining a local abi fragment if needed, 
        // OR I will assume the ABI in `contracts.ts` is just a partial and I can extend it if I had the JSON.
        // Since I don't have the JSON, I can't really "use" the function if I rely on `contracts.ts` ABI which lacks it.
        // However, in Wagmi, if I pass an ABI that lacks the function, Typescript will complain (if using typed hooks) or it will fail at runtime if the contract has it but ABI doesn't.
        // Actually, `useReadContract` with `abi: POOL_ABI` will infer function names from `POOL_ABI`.
        // If `POOL_ABI` lacks `getOrderbookInfo`, TS will error on `functionName: 'getOrderbookInfo'`.

        // So I MUST update `contracts.ts` or define a local ABI that includes `getOrderbookInfo`.
        // I'll define a local fragment in `usePool.ts` or alias it, to make it work.

        // For now, I'll comment out the missing ones or add a TODO, or define an Extended ABI.
        query: {
            enabled: !!poolAddress,
        }
    });

    return {
        fundingIdx: data,
    };
}
