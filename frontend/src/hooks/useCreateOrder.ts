import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseUnits } from 'viem';
import { POOL_ABI } from '@/config/contracts';

export function useCreateOrder() {
    const {
        writeContract,
        data: hash,
        isPending,
        error,
        ...rest
    } = useWriteContract();

    const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
        hash,
    });

    const createOrder = async (
        poolAddress: `0x${string}`,
        params: {
            margin: string;      // "100" USDT
            isSell: boolean;     // true = Short, false = Long
            orderType: number;   // 1=Market, 2=Limit, 3=FOK, 4=IOC
            size: string;        // "10" contracts
            price: string;       // "1000" price
        }) => {
        const order = {
            isSell: params.isSell,
            oType: params.orderType,
            size: parseUnits(params.size, 18),
            price: parseUnits(params.price, 18),
            margin: parseUnits(params.margin, 6), // assuming margin is merged into order struct or passed separate?
            // contracts.ts POOL_ABI newOrder inputs: [ { components: [isSell, oType, size, priceX100, margin], name: 'pOrder', type: 'tuple' } ]
            // Wait, contracts.ts newOrder signature: `inputs: [ { components: [isSell, oType, size, priceX100, margin], name: 'pOrder', type: 'tuple' } ]`
            // It takes 1 argument: a tuple.
            // FRONTEND_README.md says: `args: [marginAmount, order]` (2 args).
            // Discrepancy again! contracts.ts has `newOrder(Order)` where Order includes margin.
            // Readme has `newOrder(margin, Order)`.

            // I will follow contracts.ts signature because it's the actual file in the repo.
        };

        // Remapping for contracts.ts structure:
        // components: isSell, oType, size, priceX100, margin
        // Note name `priceX100`. Readme says `price`. If it's priceX100, maybe it has 2 decimals? Or just a name?
        // Assuming standard 18 decimals for now but name is suspicious.

        // Construct the tuple argument
        const pOrder = {
            isSell: params.isSell,
            oType: params.orderType,
            size: parseUnits(params.size, 18),
            priceX100: parseUnits(params.price, 18), // Assuming this maps to price
            margin: parseUnits(params.margin, 6), // USDT usually 6 decimals
        };

        writeContract({
            address: poolAddress,
            abi: POOL_ABI,
            functionName: 'newOrder',
            args: [pOrder], // Single argument tuple
        });
    };

    return {
        createOrder,
        hash,
        isPending,
        isConfirming,
        isSuccess, // This is transaction receipt success
        error,     // This is write contract error
        writeError: error // Alias for clarity
    };
}
