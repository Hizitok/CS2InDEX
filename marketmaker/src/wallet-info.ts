/**
 * Show market maker wallet address and ETH balance.
 * Usage: npm run wallet
 */
import { privateKeyToAccount } from 'viem/accounts';
import { createPublicClient, http, formatEther } from 'viem';
import { CONFIG } from './config';

async function main() {
    const account = privateKeyToAccount(CONFIG.privateKey);

    console.log('');
    console.log('=== Market Maker Wallet ===');
    console.log('Address :', account.address);
    console.log('Network :', CONFIG.rpcUrl);

    try {
        const pub = createPublicClient({ transport: http(CONFIG.rpcUrl) });
        const ethBal  = await pub.getBalance({ address: account.address });
        console.log('ETH Bal :', formatEther(ethBal), 'ETH',
            ethBal === 0n ? '  ← needs gas!' : '');
    } catch {
        console.log('ETH Bal : (could not connect to RPC)');
    }

    console.log('');
    console.log('Send Unichain Sepolia ETH to fund this wallet:');
    console.log(account.address);
    console.log('');
}

main().catch(console.error);
