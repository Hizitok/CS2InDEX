/**
 * CS2InDEX Market Maker Bot
 *
 * Strategy:
 *   Grid  — maintains N bid levels below mid and N ask levels above mid,
 *           each separated by `gridStep`. When a level is filled (pendingOpen→open)
 *           a close order is immediately placed at the opposite side's adjacent grid
 *           price (take-profit). If the close settles as a loss the next grid round
 *           applies the martingale multiplier.
 *
 *   Martingale — tracks consecutive losses per side. After each loss the order size
 *           for that side is multiplied by `martingaleMult`. After `martingaleMaxLevel`
 *           consecutive losses the multiplier resets to prevent infinite exposure.
 */

import {
    createPublicClient, createWalletClient, http,
    parseUnits, formatUnits,
    type PublicClient, type WalletClient, type Account,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { CONFIG } from './config';
import {
    POOL_ABI, POSITION_NFT_ABI, VAULT_ABI, ERC20_ABI,
    ORDER_TYPE, POS_STATUS,
} from './contracts';
import type { GridSlot, Side, TradeResult } from './types';

// ── Scale helpers ──────────────────────────────────────────────────────────────
const SCALE = 10n ** BigInt(CONFIG.pxDecimals);
const toChain  = (n: number) => BigInt(Math.round(n * 10 ** CONFIG.pxDecimals));
const fromChain = (n: bigint) => Number(n) / 10 ** CONFIG.pxDecimals;

// ── Logging ────────────────────────────────────────────────────────────────────
const log  = (...args: unknown[]) => console.log(`[${new Date().toISOString()}]`, ...args);
const warn = (...args: unknown[]) => console.warn(`[${new Date().toISOString()}] WARN`, ...args);
const err  = (...args: unknown[]) => console.error(`[${new Date().toISOString()}] ERR`, ...args);

// ── Position NFT address (fetched from pool at startup) ────────────────────────
let positionNFTAddress: `0x${string}` = '0x0000000000000000000000000000000000000000';

export class MarketMaker {
    private pub:    PublicClient;
    private wallet: WalletClient;
    private account: Account;

    // Grid state — indexed by slot key = `${side}-${priceRounded}`
    private slots = new Map<string, GridSlot>();

    // Martingale state per side
    private lossStreak = { buy: 0, sell: 0 };

    // History
    private tradeHistory: TradeResult[] = [];

    constructor() {
        this.account = privateKeyToAccount(CONFIG.privateKey);
        this.pub = createPublicClient({ transport: http(CONFIG.rpcUrl) }) as PublicClient;
        this.wallet = createWalletClient({
            account: this.account,
            transport: http(CONFIG.rpcUrl),
        }) as WalletClient;
    }

    // ── Write serialization queue (prevents nonce conflicts on concurrent writes) ─
    // Each writePool call chains onto this promise so writes are always sequential.
    private writeQueue: Promise<unknown> = Promise.resolve();

    // posIds for which a market-close was submitted but not yet confirmed on-chain.
    // Prevents closeOrphanPositions from re-submitting closes every tick while
    // a previous close tx is still in flight (RPC may still show status=open).
    private orphanCloseInProgress = new Set<bigint>();

    // ── Public entry ────────────────────────────────────────────────────────────

    async run() {
        log('Market maker starting up…');
        log('Account:', this.account.address);
        log('Pool:   ', CONFIG.poolAddress);

        await this.checkBalanceAndApprove();
        await this.initPositionNFT();
        log('Position NFT:', positionNFTAddress);

        // Close any orphan open positions left from previous runs before placing grid
        await this.closeOrphanPositions();

        // First grid placement
        const mid = await this.getMidPrice();
        log(`Mid price: ${mid}`);
        await this.refreshGrid(mid);

        // Poll loop
        setInterval(async () => {
            try { await this.tick(); } catch (e) { err('tick error:', e); }
        }, CONFIG.pollInterval);
    }

    // ── Tick ────────────────────────────────────────────────────────────────────

    private async tick() {
        const mid = await this.getMidPrice();

        // 1. Check every tracked slot for status changes
        for (const slot of this.slots.values()) {
            if (slot.posId !== null) {
                await this.checkSlot(slot);
            }
        }

        // 2. Close any open positions not tracked in slots (e.g. orphaned from prev run)
        await this.closeOrphanPositions();

        // 3. Fill in missing grid slots around current mid.
        //    Existing pending orders are NEVER cancelled due to price movement —
        //    they stay in the book and fill naturally.
        await this.fillMissingSlots(mid);
    }

    // ── Grid management ─────────────────────────────────────────────────────────

    private async refreshGrid(mid: number) {
        this.slots.clear();
        const step = CONFIG.gridStep;
        const n = CONFIG.gridLevels;

        // Sequential — parallel placement causes nonce conflicts.
        for (let i = 1; i <= n; i++) {
            await this.placeGridOrder('buy',  mid - step * i).catch(e => warn(`refreshGrid buy ${i} failed:`, e));
            await this.placeGridOrder('sell', mid + step * i).catch(e => warn(`refreshGrid sell ${i} failed:`, e));
        }
    }

    private async fillMissingSlots(mid: number) {
        const step = CONFIG.gridStep;
        for (let i = 1; i <= CONFIG.gridLevels; i++) {
            for (const side of ['buy', 'sell'] as Side[]) {
                const price = side === 'buy'
                    ? mid - step * i
                    : mid + step * i;
                const key = slotKey(side, price);
                const slot = this.slots.get(key);
                if (!slot || slot.posId === null) {
                    await this.placeGridOrder(side, price).catch(e =>
                        warn(`Failed to fill slot ${key}:`, e)
                    );
                }
            }
        }
    }

    private async cancelStaleOrders(newMid: number) {
        const step = CONFIG.gridStep;
        const n = CONFIG.gridLevels;
        const validPrices = new Set<string>();
        for (let i = 1; i <= n; i++) {
            validPrices.add(slotKey('buy',  newMid - step * i));
            validPrices.add(slotKey('sell', newMid + step * i));
        }

        for (const [key, slot] of this.slots.entries()) {
            if (!validPrices.has(key) && slot.posId !== null &&
                slot.status === POS_STATUS.pendingOpen) {
                await this.cancelOrder(slot.posId).catch(e =>
                    warn(`Cancel failed for ${key}:`, e)
                );
                slot.posId = null;
            }
        }
    }

    private async gridNeedsRefresh(mid: number): Promise<boolean> {
        // Find the effective center of current grid from placed slots
        const buys  = [...this.slots.values()].filter(s => s.side === 'buy');
        const sells = [...this.slots.values()].filter(s => s.side === 'sell');
        if (buys.length === 0 || sells.length === 0) return true;

        const gridMid =
            (Math.max(...buys.map(s => s.price)) +
             Math.min(...sells.map(s => s.price))) / 2;

        return Math.abs(mid - gridMid) > CONFIG.gridStep * 1.5;
    }

    // ── Order placement ─────────────────────────────────────────────────────────

    private async placeGridOrder(side: Side, rawPrice: number): Promise<void> {
        const price  = Math.round(rawPrice * 1e2) / 1e2; // 2 dp
        const key    = slotKey(side, price);
        const isSell = side === 'sell';

        const mult   = this.martingaleMult(side);
        const size   = CONFIG.baseSize   * mult;
        const margin = CONFIG.baseMargin * mult;

        log(`Placing ${side} order @ ${price} sz=${size} margin=${margin} (×${mult})`);

        try {
            const posId = await this.writePool('newOrder', [
                toChain(margin),
                {
                    isSell,
                    oType: ORDER_TYPE.Limit,
                    size:  toChain(size),
                    price: toChain(price),
                },
            ]);

            const slot: GridSlot = { side, price, size, margin, posId: posId as bigint, status: POS_STATUS.pendingOpen };
            this.slots.set(key, slot);
            log(`  → posId ${posId}`);
        } catch (e) {
            warn(`  placeGridOrder ${key} failed:`, e);
        }
    }

    // ── Slot monitoring & auto-close ────────────────────────────────────────────

    private async checkSlot(slot: GridSlot): Promise<void> {
        if (!slot.posId) return;
        const pos = await this.getPosition(slot.posId);
        if (!pos) return;

        slot.status = pos.status;

        if (pos.status === POS_STATUS.open && pos.pendingSize === 0n) {
            // Fully filled open position — place close order
            log(`Slot ${slotKey(slot.side, slot.price)} filled → placing close order`);
            await this.placeCloseOrder(slot, pos);
        } else if (pos.status === POS_STATUS.settled) {
            // Position is settled — record outcome and clear slot
            const openAmt  = Number(pos.openAmount);
            const closeAmt = Number(pos.closeAmount);
            const isWin    = slot.side === 'buy'
                ? closeAmt > openAmt
                : openAmt  > closeAmt;

            this.tradeHistory.push({ posId: slot.posId!, isWin, side: slot.side, price: slot.price });
            log(`  Settled posId=${slot.posId} ${isWin ? 'WIN' : 'LOSS'}`);

            if (isWin) {
                this.lossStreak[slot.side] = 0;
            } else {
                this.lossStreak[slot.side] = Math.min(
                    this.lossStreak[slot.side] + 1,
                    CONFIG.martingaleMaxLevel,
                );
                warn(`  Loss streak ${slot.side}: ${this.lossStreak[slot.side]}`);
            }

            slot.posId  = null;
            slot.status = POS_STATUS.settled;
        }
    }

    private async placeCloseOrder(
        slot: GridSlot,
        pos: { openSize: bigint; isShort: boolean },
    ): Promise<void> {
        // Close direction is opposite to open direction
        const closeSide = slot.side === 'buy' ? 'sell' : 'buy';
        // Take-profit: one grid step away from fill price
        const closePrice = closeSide === 'sell'
            ? slot.price + CONFIG.gridStep
            : slot.price - CONFIG.gridStep;

        log(`  Close order: ${closeSide} @ ${closePrice}`);
        try {
            await this.writePool('closePosition', [
                slot.posId!,
                {
                    isSell: closeSide === 'sell',
                    oType:  ORDER_TYPE.Limit,
                    size:   pos.openSize,
                    price:  toChain(closePrice),
                },
            ]);
        } catch (e) {
            warn(`  closePosition failed for posId=${slot.posId}:`, e);
        }
    }

    private async cancelOrder(posId: bigint): Promise<void> {
        log(`Cancelling posId=${posId}`);
        await this.writePool('cancelOrder', [posId]);
    }

    // ── Self-trade close (orphan cleanup) ────────────────────────────────────────

    /**
     * Scan all positions owned by this account on-chain. For any that are fully
     * open (status=open, no pending close) and NOT already tracked in slots with
     * a pending-close, place a Market close order.
     *
     * The Market close order hits the best available bid/ask in the pool, which is
     * typically the bot's own grid limit orders — achieving self-trade settlement.
     * This also handles positions left open after a bot restart.
     */
    async closeOrphanPositions(): Promise<void> {
        let result: [readonly bigint[], readonly {
            isShort: boolean; status: number;
            openMargin: bigint; pendingSize: bigint; openSize: bigint; closeSize: bigint;
            openAmount: bigint; closeAmount: bigint;
            openFundingIdx: bigint; closeFundingIdx: bigint;
        }[]];

        try {
            result = await this.pub.readContract({
                address: positionNFTAddress,
                abi: POSITION_NFT_ABI,
                functionName: 'getPositionsByOwner',
                args: [this.account.address],
            }) as typeof result;
        } catch (e) {
            warn('closeOrphanPositions: getPositionsByOwner failed:', e);
            return;
        }

        const [tokenIds, positions] = result;

        // Batch-lookup pool address for each position in parallel
        const poolAddrs = await Promise.all(
            tokenIds.map(id => this.pub.readContract({
                address: positionNFTAddress,
                abi: POSITION_NFT_ABI,
                functionName: 'getPool',
                args: [id],
            }) as Promise<`0x${string}`>)
        );

        // Clear orphanCloseInProgress for any posId no longer in open state
        // (it has been mined as pendingClose/closed, or the NFT was burned)
        const openPosIds = new Set<bigint>(
            tokenIds.filter((_, i) => positions[i].status === POS_STATUS.open)
        );
        for (const id of this.orphanCloseInProgress) {
            if (!openPosIds.has(id)) this.orphanCloseInProgress.delete(id);
        }

        // Build set of posIds already tracked with a pending-close
        const pendingClose = new Set<bigint>(
            [...this.slots.values()]
                .filter(s => s.posId !== null && s.status === POS_STATUS.pendingClose)
                .map(s => s.posId!)
        );

        let closed = 0;
        for (let i = 0; i < tokenIds.length; i++) {
            const posId = tokenIds[i];
            const pos   = positions[i];

            // Only target fully open positions on this pool
            if (pos.status !== POS_STATUS.open) continue;
            if (poolAddrs[i].toLowerCase() !== CONFIG.poolAddress.toLowerCase()) continue;
            if (pendingClose.has(posId)) continue;
            if (this.orphanCloseInProgress.has(posId)) continue; // close already in flight

            // Long (isShort=false) → close with sell (isSell=true)
            // Short (isShort=true) → close with buy  (isSell=false)
            const isSell = !pos.isShort;
            log(`Self-trade close: posId=${posId} ${pos.isShort ? 'short' : 'long'} size=${pos.openSize}`);

            // Mark as in-flight BEFORE submitting so concurrent ticks don't double-send
            this.orphanCloseInProgress.add(posId);
            try {
                await this.writePool('closePosition', [
                    posId,
                    {
                        isSell,
                        oType:  ORDER_TYPE.Market, // market order → matches bot's own limit orders
                        size:   pos.openSize,
                        price:  0n,
                    },
                ]);
                closed++;
                log(`  → closed posId=${posId}`);
            } catch (e) {
                // Remove from in-flight on failure so the next tick can retry
                this.orphanCloseInProgress.delete(posId);
                warn(`  self-trade close failed for posId=${posId}:`, e);
            }
        }

        if (closed > 0) log(`closeOrphanPositions: closed ${closed} position(s)`);
    }

    // ── Martingale ──────────────────────────────────────────────────────────────

    private martingaleMult(side: Side): number {
        const streak = this.lossStreak[side];
        if (streak === 0) return 1;
        // 2^streak, capped at CONFIG.martingaleMaxLevel doublings
        const capped = Math.min(streak, CONFIG.martingaleMaxLevel);
        return Math.min(CONFIG.martingaleMult ** capped, 2 ** CONFIG.martingaleMaxLevel);
    }

    // ── Chain helpers ────────────────────────────────────────────────────────────

    private async getMidPrice(): Promise<number> {
        const [lastPrice, oraclePrice] = await Promise.all([
            this.pub.readContract({
                address: CONFIG.poolAddress,
                abi: POOL_ABI,
                functionName: 'getLastPrice',
            }),
            this.pub.readContract({
                address: CONFIG.poolAddress,
                abi: POOL_ABI,
                functionName: 'oraclePrice',
            }),
        ]) as [bigint, bigint];

        // Use oracle price if last price is 0 (no trades yet)
        const raw = lastPrice > 0n ? lastPrice : oraclePrice;
        return fromChain(raw);
    }

    private async getPosition(posId: bigint) {
        try {
            const pos = await this.pub.readContract({
                address: positionNFTAddress,
                abi: POSITION_NFT_ABI,
                functionName: 'getPosition',
                args: [posId],
            }) as {
                isShort: boolean; status: number;
                openMargin: bigint; pendingSize: bigint; openSize: bigint; closeSize: bigint;
                openAmount: bigint; closeAmount: bigint;
                openFundingIdx: bigint; closeFundingIdx: bigint;
            };
            return pos;
        } catch (e) {
            warn(`getPosition(${posId}) failed:`, e);
            return null;
        }
    }

    // Generic pool write — returns the contract's return value (via simulateContract).
    // Serialized through writeQueue to prevent nonce conflicts on concurrent calls.
    private writePool(functionName: string, args: unknown[]): Promise<unknown> {
        const next = this.writeQueue.then(() => this._doWrite(functionName, args));
        // Swallow errors in the queue chain so subsequent writes still proceed
        this.writeQueue = next.catch(() => {});
        return next;
    }

    private async _doWrite(functionName: string, args: unknown[]): Promise<unknown> {
        const { request, result } = await this.pub.simulateContract({
            address: CONFIG.poolAddress,
            abi: POOL_ABI,
            functionName: functionName as any,
            args: args as any,
            account: this.account,
        });
        const hash = await this.wallet.writeContract(request as any);
        const receipt = await this.pub.waitForTransactionReceipt({ hash });
        if (receipt.status !== 'success') throw new Error(`tx reverted: ${hash}`);

        // For newOrder: parse the actual posId from the NFT Transfer(mint) event.
        // simulateContract result can lag on distributed RPC nodes — the next tx's
        // simulation may see stale tokenCount and return the same posId as the previous tx.
        if (functionName === 'newOrder') {
            // ERC721 Transfer: keccak256("Transfer(address,address,uint256)")
            const TRANSFER_SIG = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef';
            const ZERO_TOPIC   = '0x0000000000000000000000000000000000000000000000000000000000000000';
            const mintLog = receipt.logs.find(log =>
                log.address.toLowerCase() === positionNFTAddress.toLowerCase() &&
                log.topics[0] === TRANSFER_SIG &&
                log.topics[1] === ZERO_TOPIC          // from = address(0) → mint
            );
            if (mintLog?.topics[3]) {
                return BigInt(mintLog.topics[3]);
            }
            warn('newOrder: no NFT mint event found in receipt, falling back to simulation result');
        }

        return result;
    }

    private async initPositionNFT() {
        // Read positionNFT address from pool's public variable
        const addr = await this.pub.readContract({
            address: CONFIG.poolAddress,
            abi: [{
                inputs: [],
                name: 'positionNFT',
                outputs: [{ name: '', type: 'address' }],
                stateMutability: 'view',
                type: 'function',
            }] as const,
            functionName: 'positionNFT',
        });
        positionNFTAddress = addr as `0x${string}`;
    }

    private async checkBalanceAndApprove() {
        // Minimum Vault balance needed for this grid config (with 2× safety buffer)
        const minRequired = toChain(
            CONFIG.baseMargin * CONFIG.gridLevels * 2 *
            CONFIG.martingaleMult ** CONFIG.martingaleMaxLevel * 2
        );

        // ── 1. Check current Vault balance ──────────────────────────────────────
        const vaultBal = await this.pub.readContract({
            address: CONFIG.vaultAddress,
            abi: VAULT_ABI,
            functionName: 'balanceOf',
            args: [this.account.address],
        }) as bigint;

        log(`Vault balance: ${fromChain(vaultBal)} USDC (need ${fromChain(minRequired)})`);

        if (vaultBal >= minRequired) return; // already funded, done

        const needed = minRequired - vaultBal;
        log(`Vault underfunded by ${fromChain(needed)} USDC — auto-funding…`);

        // ── 2. Check USDC wallet balance, mint if needed ────────────────────────
        const walletBal = await this.pub.readContract({
            address: CONFIG.tokenAddress,
            abi: ERC20_ABI,
            functionName: 'balanceOf',
            args: [this.account.address],
        }) as bigint;

        if (walletBal < needed) {
            const mintAmt = needed - walletBal;
            log(`Minting ${fromChain(mintAmt)} MockUSDC…`);
            const { request: mintReq } = await this.pub.simulateContract({
                address: CONFIG.tokenAddress,
                abi: ERC20_ABI,
                functionName: 'mint',
                args: [this.account.address, mintAmt],
                account: this.account,
            });
            const mintHash = await this.wallet.writeContract(mintReq as any);
            await this.pub.waitForTransactionReceipt({ hash: mintHash });
            log(`  → minted, tx: ${mintHash}`);
        }

        // ── 3. Approve Vault if allowance is insufficient ───────────────────────
        const allowance = await this.pub.readContract({
            address: CONFIG.tokenAddress,
            abi: ERC20_ABI,
            functionName: 'allowance',
            args: [this.account.address, CONFIG.vaultAddress],
        }) as bigint;

        if (allowance < needed) {
            log(`Approving Vault for max USDC…`);
            const { request: approveReq } = await this.pub.simulateContract({
                address: CONFIG.tokenAddress,
                abi: ERC20_ABI,
                functionName: 'approve',
                args: [CONFIG.vaultAddress, BigInt(2) ** BigInt(256) - BigInt(1)],
                account: this.account,
            });
            const approveHash = await this.wallet.writeContract(approveReq as any);
            await this.pub.waitForTransactionReceipt({ hash: approveHash });
            log(`  → approved, tx: ${approveHash}`);
        }

        // ── 4. Deposit into Vault ───────────────────────────────────────────────
        log(`Depositing ${fromChain(needed)} USDC into Vault…`);
        const { request: depReq } = await this.pub.simulateContract({
            address: CONFIG.vaultAddress,
            abi: VAULT_ABI,
            functionName: 'deposit',
            args: [needed],
            account: this.account,
        });
        const depHash = await this.wallet.writeContract(depReq as any);
        await this.pub.waitForTransactionReceipt({ hash: depHash });
        log(`  → deposited, tx: ${depHash}`);
    }
}

// ── Utilities ─────────────────────────────────────────────────────────────────
function slotKey(side: Side, price: number): string {
    return `${side}-${price.toFixed(4)}`;
}
