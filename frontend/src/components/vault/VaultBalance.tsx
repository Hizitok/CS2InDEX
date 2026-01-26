'use client';

import { useState } from 'react';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { formatUnits, parseUnits } from 'viem';
import { VAULT_ABI, ERC20_ABI, CONTRACTS } from '@/config/contracts';
import toast from 'react-hot-toast';
import { Wallet, ArrowDownToLine, ArrowUpFromLine } from 'lucide-react';

export function VaultBalance() {
  const { address } = useAccount();
  const [mode, setMode] = useState<'deposit' | 'withdraw'>('deposit');
  const [amount, setAmount] = useState('');

  // Read balances
  const { data: vaultBalance } = useReadContract({
    address: CONTRACTS.VAULT,
    abi: VAULT_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 5000 },
  });

  const { data: availableBalance } = useReadContract({
    address: CONTRACTS.VAULT,
    abi: VAULT_ABI,
    functionName: 'availableBalance',
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 5000 },
  });

  const { data: usdcBalance } = useReadContract({
    address: CONTRACTS.USDC,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 5000 },
  });

  const { data: allowance } = useReadContract({
    address: CONTRACTS.USDC,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: address ? [address, CONTRACTS.VAULT] : undefined,
    query: { enabled: !!address },
  });

  // Write contracts
  const { writeContract: approve, data: approveHash } = useWriteContract();
  const { writeContract: deposit, data: depositHash } = useWriteContract();
  const { writeContract: withdraw, data: withdrawHash } = useWriteContract();

  const { isLoading: isApproving } = useWaitForTransactionReceipt({ hash: approveHash });
  const { isLoading: isDepositing } = useWaitForTransactionReceipt({ hash: depositHash });
  const { isLoading: isWithdrawing } = useWaitForTransactionReceipt({ hash: withdrawHash });

  const needsApproval = amount && allowance !== undefined
    ? parseUnits(amount, 6) > (allowance as bigint)
    : false;

  const handleApprove = async () => {
    try {
      approve({
        address: CONTRACTS.USDC,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [CONTRACTS.VAULT, parseUnits(amount, 6)],
      });
      toast.success('Approval submitted!');
    } catch (error: any) {
      toast.error(error.message || 'Approval failed');
    }
  };

  const handleDeposit = async () => {
    try {
      deposit({
        address: CONTRACTS.VAULT,
        abi: VAULT_ABI,
        functionName: 'deposit',
        args: [parseUnits(amount, 6)],
      });
      toast.success('Deposit submitted!');
      setAmount('');
    } catch (error: any) {
      toast.error(error.message || 'Deposit failed');
    }
  };

  const handleWithdraw = async () => {
    try {
      withdraw({
        address: CONTRACTS.VAULT,
        abi: VAULT_ABI,
        functionName: 'withdraw',
        args: [parseUnits(amount, 6)],
      });
      toast.success('Withdrawal submitted!');
      setAmount('');
    } catch (error: any) {
      toast.error(error.message || 'Withdrawal failed');
    }
  };

  const formattedVaultBalance = vaultBalance ? formatUnits(vaultBalance as bigint, 6) : '0';
  const formattedAvailableBalance = availableBalance ? formatUnits(availableBalance as bigint, 6) : '0';
  const formattedUsdcBalance = usdcBalance ? formatUnits(usdcBalance as bigint, 6) : '0';
  const lockedBalance = vaultBalance && availableBalance
    ? formatUnits((vaultBalance as bigint) - (availableBalance as bigint), 6)
    : '0';

  if (!address) return null;

  return (
    <div className="card">
      <div className="flex items-center gap-2 mb-6">
        <Wallet className="text-primary-500" size={24} />
        <h2 className="text-xl font-bold">Vault Balance</h2>
      </div>

      {/* Balances */}
      <div className="space-y-3 mb-6">
        <div className="bg-gray-700/50 rounded-lg p-4">
          <div className="text-sm text-gray-400">Total</div>
          <div className="text-2xl font-bold">{formattedVaultBalance} USDC</div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="bg-gray-700/50 rounded-lg p-3">
            <div className="text-xs text-gray-400">Available</div>
            <div className="text-lg font-semibold text-green-500">
              {formattedAvailableBalance}
            </div>
          </div>
          <div className="bg-gray-700/50 rounded-lg p-3">
            <div className="text-xs text-gray-400">Locked</div>
            <div className="text-lg font-semibold text-orange-500">
              {lockedBalance}
            </div>
          </div>
        </div>

        <div className="text-sm text-gray-400">
          Wallet: {formattedUsdcBalance} USDC
        </div>
      </div>

      {/* Deposit/Withdraw Toggle */}
      <div className="grid grid-cols-2 gap-2 mb-4">
        <button
          onClick={() => setMode('deposit')}
          className={`py-2 rounded-lg font-medium transition-colors flex items-center justify-center gap-2 ${
            mode === 'deposit'
              ? 'bg-primary-600 text-white'
              : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
          }`}
        >
          <ArrowDownToLine size={16} />
          Deposit
        </button>
        <button
          onClick={() => setMode('withdraw')}
          className={`py-2 rounded-lg font-medium transition-colors flex items-center justify-center gap-2 ${
            mode === 'withdraw'
              ? 'bg-primary-600 text-white'
              : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
          }`}
        >
          <ArrowUpFromLine size={16} />
          Withdraw
        </button>
      </div>

      {/* Input */}
      <div className="space-y-4">
        <div>
          <input
            type="number"
            className="input"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
            step="0.01"
            min="0"
          />
          <div className="flex justify-between mt-2 text-sm text-gray-400">
            <span>USDC</span>
            <button
              onClick={() => setAmount(
                mode === 'deposit' ? formattedUsdcBalance : formattedAvailableBalance
              )}
              className="text-primary-500 hover:text-primary-400"
            >
              Max: {mode === 'deposit' ? formattedUsdcBalance : formattedAvailableBalance}
            </button>
          </div>
        </div>

        {mode === 'deposit' && needsApproval ? (
          <button
            onClick={handleApprove}
            disabled={isApproving || !amount}
            className="w-full btn-primary"
          >
            {isApproving ? 'Approving...' : 'Approve USDC'}
          </button>
        ) : (
          <button
            onClick={mode === 'deposit' ? handleDeposit : handleWithdraw}
            disabled={
              (mode === 'deposit' ? isDepositing : isWithdrawing) ||
              !amount ||
              parseFloat(amount) <= 0
            }
            className="w-full btn-primary"
          >
            {mode === 'deposit'
              ? isDepositing ? 'Depositing...' : 'Deposit'
              : isWithdrawing ? 'Withdrawing...' : 'Withdraw'
            }
          </button>
        )}
      </div>
    </div>
  );
}
