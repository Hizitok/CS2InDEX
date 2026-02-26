export type Side = 'buy' | 'sell';

/** A grid slot — one level in the order ladder */
export interface GridSlot {
    side:      Side;
    price:     number;   // human-readable (not scaled)
    size:      number;   // human-readable
    margin:    number;   // human-readable USDC
    /** Position NFT id if an open order exists for this slot, else null */
    posId:     bigint | null;
    /** Status as last polled from chain */
    status:    number;
}

/** Recorded outcome of a closed trade for martingale bookkeeping */
export interface TradeResult {
    posId:  bigint;
    isWin:  boolean;  // true if PnL > 0
    side:   Side;
    price:  number;
}
