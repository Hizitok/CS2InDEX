import { useWriteContract } from 'wagmi';
import { parseUnits } from 'viem';
import { POOL_ABI } from '@/config/contracts';

export function useClosePosition() {
    const { writeContract, ...rest } = useWriteContract();

    const closePosition = (
        poolAddress: `0x${string}`,
        orderId: bigint,
        size: string,
        price: string,
        isSell: boolean,
        marginStr: string = '0'
    ) => {
        // contract.ts closePosition inputs: [orderId, pOrder]
        // pOrder components: isSell, oType, size, priceX100, margin

        const pOrder = {
            isSell, // Opposite of position side? Usually close order is opposite.
            oType: 2, // Limit order
            size: parseUnits(size, 18),
            priceX100: parseUnits(price, 18),
            margin: parseUnits(marginStr, 6),
        };

        writeContract({
            address: poolAddress,
            abi: POOL_ABI,
            functionName: 'closePosition',
            args: [orderId, pOrder],
        });
    };

    return { closePosition, ...rest };
}
