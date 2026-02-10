import { useWriteContract } from 'wagmi';
import { parseUnits } from 'viem';
import { POOL_ABI, PX_DECIMALS, ORDER_TYPE } from '@/config/contracts';

export function useClosePosition() {
    const { writeContract, ...rest } = useWriteContract();

    const closePosition = (
        poolAddress: `0x${string}`,
        orderId: bigint,
        size: string,
        price: string,
        isSell: boolean,
    ) => {
        // PoolOrder struct: { isSell, oType, size, price } — no margin field
        const pOrder = {
            isSell,
            oType: ORDER_TYPE.Limit,
            size: parseUnits(size, PX_DECIMALS),
            price: parseUnits(price, PX_DECIMALS),
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
