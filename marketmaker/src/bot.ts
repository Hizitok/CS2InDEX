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

    // ── Public entry ────────────────────────────────────────────────────────────

    async run() {
        log('Market maker starting up…');
        log('Account:', this.account.address);
        log('Pool:   ', CONFIG.poolAddress);

        await this.checkBalanceAndApprove();
        await this.initPositionNFT();
        log('Position NFT:', positionNFTAddress);

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

        // 2. Refresh grid if price has moved more than 1.5 steps from center
        const needsRefresh = await this.gridNeedsRefresh(mid);
        if (needsRefresh) {
            log(`Price moved to ${mid}, refreshing grid…`);
            await this.cancelStaleOrders(mid);
            await this.refreshGrid(mid);
        } else {
            // Only fill in any missing open slots
            await this.fillMissingSlots(mid);
        }
    }

    // ── Grid management ─────────────────────────────────────────────────────────

    private async refreshGrid(mid: number) {
        this.slots.clear();
        const step = CONFIG.gridStep;
        const n = CONFIG.gridLevels;

        const promises: Promise<void>[] = [];
        for (let i = 1; i <= n; i++) {
            promises.push(this.placeGridOrder('buy',  mid - step * i));
            promises.push(this.placeGridOrder('sell', mid + step * i));
        }
        await Promise.allSettled(promises);
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
                positionID: bigint; pool: string; isShort: boolean; status: number;
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

    // Generic pool write — returns the uint256 return value if any
    private async writePool(functionName: string, args: unknown[]): Promise<unknown> {
        const { request } = await this.pub.simulateContract({
            address: CONFIG.poolAddress,
            abi: POOL_ABI,
            functionName: functionName as any,
            args: args as any,
            account: this.account,
        });
        const hash = await this.wallet.writeContract(request as any);
        const receipt = await this.pub.waitForTransactionReceipt({ hash });
        if (receipt.status !== 'success') throw new Error(`tx reverted: ${hash}`);

        // Decode return value from the first log or just return hash for now
        // (viem simulateContract gives us the result)
        return (request as any).result ?? hash;
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
        const balance = await this.pub.readContract({
            address: CONFIG.vaultAddress,
            abi: VAULT_ABI,
            functionName: 'balanceOf',
            args: [this.account.address],
        }) as bigint;

        const minRequired = toChain(
            CONFIG.baseMargin * CONFIG.gridLevels * 2 *
            CONFIG.martingaleMult ** CONFIG.martingaleMaxLevel
        );

        if (balance < minRequired) {
            warn(`Vault balance (${fromChain(balance)} USDC) below recommended minimum.`);
            warn(`Deposit more funds or reduce grid parameters.`);
        } else {
            log(`Vault balance: ${fromChain(balance)} USDC`);
        }
    }
}

// ── Utilities ─────────────────────────────────────────────────────────────────
function slotKey(side: Side, price: number): string {
    return `${side}-${price.toFixed(4)}`;
}
