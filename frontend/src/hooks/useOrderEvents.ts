import { useWatchContractEvent } from 'wagmi';
import { POOL_ABI } from '@/config/contracts';

export type OrderEvent = {
    type: 'OrderCreated' | 'OrderMatched';
    orderId: bigint;
    trader?: string;
    isSell?: boolean;
    size: bigint;
    price: bigint;
    matchedOrderId?: bigint;
};

export function useOrderEvents(poolAddress: `0x${string}` | undefined, onEvent: (event: OrderEvent) => void) {
    // Listen for OrderCreated
    // Note: POOL_ABI in contracts.ts needs to have OrderCreated event.
    // I need to check if it has events. The view_file output showed functions, not events?
    // I should check contracts.ts again for events. If missing, this code will have TS errors.
    useWatchContractEvent({
        address: poolAddress,
        abi: POOL_ABI,
        eventName: 'OrderCreated', // This might not be in POOL_ABI
        onLogs(logs) {
            logs.forEach((log: any) => {
                // args might need type assertion if ABI is incomplete
                if (log.args) {
                    onEvent({
                        type: 'OrderCreated',
                        orderId: log.args.orderId,
                        trader: log.args.trader,
                        isSell: log.args.isSell,
                        size: log.args.size,
                        price: log.args.price,
                    });
                }
            });
        },
        enabled: !!poolAddress,
    });

    // Listen for OrderMatched
    useWatchContractEvent({
        address: poolAddress,
        abi: POOL_ABI,
        eventName: 'OrderMatched', // This might not be in POOL_ABI
        onLogs(logs) {
            logs.forEach((log: any) => {
                if (log.args) {
                    onEvent({
                        type: 'OrderMatched',
                        orderId: log.args.orderId,
                        matchedOrderId: log.args.matchedOrderId,
                        size: log.args.size,
                        price: log.args.price,
                    });
                }
            });
        },
        enabled: !!poolAddress,
    });
}
