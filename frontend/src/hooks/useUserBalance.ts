import { useReadContract, useAccount } from 'wagmi';
import { VAULT_ABI, CONTRACTS } from '@/config/contracts';

export function useUserBalance() {
    const { address } = useAccount();

    // Vault only has balanceOf(address) — no locked/available split
    const { data, isLoading } = useReadContract({
        address: CONTRACTS.VAULT,
        abi: VAULT_ABI,
        functionName: 'balanceOf',
        args: address ? [address] : undefined,
        query: {
            enabled: !!address,
        }
    });

    return {
        balance: data,
        isLoading,
    };
}
