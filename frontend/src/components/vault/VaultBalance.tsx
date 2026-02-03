'use client';

/**
 * @fileoverview 资金库管理组件 (Vault Balance)
 * 负责用户资产的存取管理，包括 USDC 的授权 (Approve)、存款 (Deposit) 和取款 (Withdraw)。
 * 遵循 Google TypeScript Style Guide。
 *
 * @author Senior Architect
 */

import { useState } from 'react';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { formatUnits, parseUnits } from 'viem';
import { VAULT_ABI, ERC20_ABI, CONTRACTS } from '@/config/contracts';
import toast from 'react-hot-toast';
import { Wallet, ArrowDownToLine, ArrowUpFromLine, Lock, Unlock } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { useLanguage } from '@/contexts/LanguageContext';

/**
 * 资金库组件
 */
export function VaultBalance() {
  const { address } = useAccount();
  const { t } = useLanguage();

  // 交互模式: 存款 / 取款
  const [mode, setMode] = useState<'deposit' | 'withdraw'>('deposit');
  const [amount, setAmount] = useState<string>('');

  // 避免重渲染的 Refetch 配置
  const readConfig = {
    query: {
      enabled: !!address,
      refetchInterval: 5000
    }
  };

  // --- 合约读取 Hooks ---

  // 1. 获取 Vault 总权益 (Total Balance in Vault)
  const { data: vaultBalance } = useReadContract({
    address: CONTRACTS.VAULT,
    abi: VAULT_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    ...readConfig
  });

  // 2. 获取可用余额 (Available to Withdraw)
  const { data: availableBalance } = useReadContract({
    address: CONTRACTS.VAULT,
    abi: VAULT_ABI,
    functionName: 'availableBalance',
    args: address ? [address] : undefined,
    ...readConfig
  });

  // 3. 获取钱包 USDC 余额
  const { data: usdcBalance } = useReadContract({
    address: CONTRACTS.USDC,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    ...readConfig
  });

  // 4. 获取 USDC 对 Vault 的授权额度
  const { data: allowance } = useReadContract({
    address: CONTRACTS.USDC,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: address ? [address, CONTRACTS.VAULT] : undefined,
    query: { enabled: !!address } // Allowance 不需要频繁轮询，除非操作后
  });

  // --- 合约写入 Hooks ---

  const { writeContract: approve, data: approveHash, error: approveError } = useWriteContract();
  const { writeContract: deposit, data: depositHash, error: depositError } = useWriteContract();
  const { writeContract: withdraw, data: withdrawHash, error: withdrawError } = useWriteContract();

  // 交易状态监听
  const { isLoading: isApproving } = useWaitForTransactionReceipt({ hash: approveHash });
  const { isLoading: isDepositing } = useWaitForTransactionReceipt({ hash: depositHash });
  const { isLoading: isWithdrawing } = useWaitForTransactionReceipt({ hash: withdrawHash });

  // 计算是否需要授权
  const needsApproval = amount && allowance !== undefined
    ? parseUnits(amount, 6) > (allowance as bigint)
    : false;

  /**
   * 处理 USDC 授权
   */
  const handleApprove = async () => {
    try {
      if (!amount) return;
      approve({
        address: CONTRACTS.USDC,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [CONTRACTS.VAULT, parseUnits(amount, 6)],
      });
      toast.loading('正在授权 USDC...');
    } catch (error: unknown) {
      console.error('Approve Error:', error);
      toast.error('授权失败');
    }
  };

  /**
   * 处理存款 logic
   */
  const handleDeposit = async () => {
    try {
      if (!amount) return;
      deposit({
        address: CONTRACTS.VAULT,
        abi: VAULT_ABI,
        functionName: 'deposit',
        args: [parseUnits(amount, 6)],
      });
      toast.loading('正在存入资金...');
      setAmount('');
    } catch (error: unknown) {
      console.error('Deposit Error:', error);
      toast.error('存款失败');
    }
  };

  /**
   * 处理取款 logic
   */
  const handleWithdraw = async () => {
    try {
      if (!amount) return;
      withdraw({
        address: CONTRACTS.VAULT,
        abi: VAULT_ABI,
        functionName: 'withdraw',
        args: [parseUnits(amount, 6)],
      });
      toast.loading('正在提取资金...');
      setAmount('');
    } catch (error: unknown) {
      console.error('Withdraw Error:', error);
      toast.error('取款失败');
    }
  };

  // 格式化数值展示
  const formattedVaultBalance = vaultBalance ? formatUnits(vaultBalance as bigint, 6) : '0';
  const formattedAvailableBalance = availableBalance ? formatUnits(availableBalance as bigint, 6) : '0';
  const formattedUsdcBalance = usdcBalance ? formatUnits(usdcBalance as bigint, 6) : '0';

  // 计算锁定金额 (用于保证金的部分)
  const lockedBalance = vaultBalance && availableBalance
    ? formatUnits((vaultBalance as bigint) - (availableBalance as bigint), 6)
    : '0';

  if (!address) return null;

  return (
    <div className="card border border-gray-700 shadow-xl bg-gray-800/60 backdrop-blur-sm h-full">
      <div className="flex items-center gap-2 mb-6 text-white">
        <Wallet className="text-secondary-500" size={24} />
        <h2 className="text-xl font-bold">{t.vault.title}</h2>
      </div>

      {/* 资产概览卡片 */}
      <div className="space-y-3 mb-6">
        <div className="bg-gradient-to-br from-gray-700/50 to-gray-800/50 rounded-xl p-5 border border-gray-600/50">
          <div className="text-sm text-gray-400 mb-1">{t.vault.total}</div>
          <div className="text-3xl font-bold text-white tracking-tight">
            ${formattedVaultBalance} <span className="text-sm font-normal text-gray-500">USDC</span>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="bg-gray-700/30 rounded-xl p-3 border border-gray-700/50">
            <div className="flex items-center gap-2 text-xs text-gray-400 mb-1">
              <Unlock size={12} /> {t.vault.available}
            </div>
            <div className="text-lg font-semibold text-green-400">
              ${formattedAvailableBalance}
            </div>
          </div>
          <div className="bg-gray-700/30 rounded-xl p-3 border border-gray-700/50">
            <div className="flex items-center gap-2 text-xs text-gray-400 mb-1">
              <Lock size={12} /> {t.vault.locked}
            </div>
            <div className="text-lg font-semibold text-orange-400">
              ${lockedBalance}
            </div>
          </div>
        </div>

        <div className="text-xs text-right text-gray-500">
          {t.trading.balance}: <span className="text-gray-300">{formattedUsdcBalance} USDC</span>
        </div>
      </div>

      {/* 操作面板 */}
      <div className="bg-gray-900/50 rounded-xl p-1 grid grid-cols-2 gap-1 mb-6">
        <button
          onClick={() => setMode('deposit')}
          className={`py-2 rounded-lg font-medium transition-all duration-200 flex items-center justify-center gap-2 text-sm ${mode === 'deposit'
            ? 'bg-gray-700 text-white shadow-md'
            : 'text-gray-400 hover:text-gray-200 hover:bg-gray-800'
            }`}
        >
          <ArrowDownToLine size={16} />
          {t.trading.deposit}
        </button>
        <button
          onClick={() => setMode('withdraw')}
          className={`py-2 rounded-lg font-medium transition-all duration-200 flex items-center justify-center gap-2 text-sm ${mode === 'withdraw'
            ? 'bg-gray-700 text-white shadow-md'
            : 'text-gray-400 hover:text-gray-200 hover:bg-gray-800'
            }`}
        >
          <ArrowUpFromLine size={16} />
          {t.trading.withdraw}
        </button>
      </div>

      {/* 数量输入 */}
      <div className="space-y-4">
        <div className="relative">
          <input
            type="number"
            className="input w-full pr-16 bg-gray-900 border-gray-700 focus:border-secondary-500"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
            step="0.01"
            min="0"
          />
          <button
            onClick={() => setAmount(
              mode === 'deposit' ? formattedUsdcBalance : formattedAvailableBalance
            )}
            className="absolute right-3 top-1/2 -translate-y-1/2 text-xs font-bold text-secondary-500 hover:text-secondary-400 px-2 py-1 rounded hover:bg-secondary-500/10 transition-colors"
          >
            MAX
          </button>
        </div>

        {/* 动作按钮 */}


        {/* Animated Action Button */}
        <AnimatePresence mode="wait">
          {mode === 'deposit' && needsApproval ? (
            <motion.button
              key="approve-btn"
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
              onClick={handleApprove}
              disabled={isApproving || !amount}
              className="w-full btn-secondary py-3 text-white font-bold rounded-xl shadow-lg shadow-blue-900/20 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isApproving ? t.vault.approving : t.vault.step1}
            </motion.button>
          ) : (
            <motion.button
              key="action-btn"
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
              onClick={mode === 'deposit' ? handleDeposit : handleWithdraw}
              disabled={
                (mode === 'deposit' ? isDepositing : isWithdrawing) ||
                !amount ||
                parseFloat(amount) <= 0
              }
              className={`w-full py-3 text-white font-bold rounded-xl shadow-lg disabled:opacity-50 disabled:cursor-not-allowed ${mode === 'deposit'
                ? 'bg-secondary-600 hover:bg-secondary-500 shadow-blue-900/20'
                : 'bg-gray-600 hover:bg-gray-500 shadow-gray-900/20'
                }`}
            >
              {mode === 'deposit'
                ? (isDepositing ? t.vault.depositing : t.vault.confirmDeposit)
                : (isWithdrawing ? t.vault.withdrawing : t.vault.confirmWithdraw)
              }
            </motion.button>
          )}
        </AnimatePresence>
      </div>

      {/* 错误提示 */}
      {(approveError || depositError || withdrawError) && (
        <div className="mt-4 p-3 bg-red-900/20 border border-red-800/50 rounded-lg text-xs text-red-300 break-words">
          {(approveError || depositError || withdrawError)?.message}
        </div>
      )}
    </div>
  );
}

