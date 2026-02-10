import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseUnits } from 'viem';
import { POOL_ABI, PX_DECIMALS, ORDER_TYPE } from '@/config/contracts';

export function useCreateOrder() {
    const {
        writeContract,
        data: hash,
        isPending,
        error,
    } = useWriteContract();

    const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
        hash,
    });

    const createOrder = async (
        poolAddress: `0x${string}`,
        params: {
            margin: string;      // "100" USDC
            isSell: boolean;     // true = Short, false = Long
            orderType: number;   // 1=Market, 2=Limit, 3=FOK, 4=IOC
            size: string;        // "10" contracts
            price: string;       // "1000" price
        }) => {
        // margin is a separate argument, not part of the order struct
        const marginAmount = parseUnits(params.margin, PX_DECIMALS);

        // PoolOrder struct: { isSell, oType, size, price }
        const pOrder = {
            isSell: params.isSell,
            oType: params.orderType,
            size: parseUnits(params.size, PX_DECIMALS),
            price: parseUnits(params.price, PX_DECIMALS),
        };

        writeContract({
            address: poolAddress,
            abi: POOL_ABI,
            functionName: 'newOrder',
            args: [marginAmount, pOrder],
        });
    };

    return {
        createOrder,
        hash,
        isPending,
        isConfirming,
        isSuccess,
        error,
    };
}
