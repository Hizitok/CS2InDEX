import { useReadContract, useAccount } from 'wagmi';
import { VAULT_ABI, CONTRACTS } from '@/config/contracts';

export function useUserBalance() {
    const { address } = useAccount();

    const { data, isLoading } = useReadContract({
        address: CONTRACTS.VAULT,
        abi: VAULT_ABI,
        functionName: 'balanceOf',
        args: address ? [address] : undefined,
        query: {
            enabled: !!address,
        }
    });

    const { data: balanceInfo } = useReadContract({
        address: CONTRACTS.VAULT,
        abi: VAULT_ABI,
        functionName: 'getUserBalanceInfo',
        args: address ? [address] : undefined,
        query: {
            enabled: !!address,
        }
    });

    return {
        balance: data, // from balanceOf
        balanceInfo, // from getUserBalanceInfo
        isLoading,
    };
}
