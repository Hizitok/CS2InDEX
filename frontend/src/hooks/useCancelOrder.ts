import { useWriteContract } from 'wagmi';
import { POOL_ABI } from '@/config/contracts';

export function useCancelOrder() {
    const { writeContract, ...rest } = useWriteContract();

    const cancelOrder = (poolAddress: `0x${string}`, orderId: bigint) => {
        writeContract({
            address: poolAddress,
            abi: POOL_ABI,
            functionName: 'cancelOrder',
            args: [orderId],
        });
    };

    return { cancelOrder, ...rest };
}
