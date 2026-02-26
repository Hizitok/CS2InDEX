import 'dotenv/config';

export const CONFIG = {
  // ── Network ──────────────────────────────────────────────────────────────
  rpcUrl:       process.env.RPC_URL       ?? 'http://127.0.0.1:8545',
  privateKey:   (process.env.PRIVATE_KEY  ?? '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80') as `0x${string}`,

  // ── Contracts ─────────────────────────────────────────────────────────────
  poolAddress:  (process.env.POOL_ADDRESS  ?? '0x0000000000000000000000000000000000000000') as `0x${string}`,
  vaultAddress: (process.env.VAULT_ADDRESS ?? '0x0000000000000000000000000000000000000000') as `0x${string}`,
  tokenAddress: (process.env.TOKEN_ADDRESS ?? '0x0000000000000000000000000000000000000000') as `0x${string}`,

  // ── Grid parameters ───────────────────────────────────────────────────────
  /** Number of buy levels and sell levels on each side of mid */
  gridLevels:   Number(process.env.GRID_LEVELS  ?? 4),
  /** Price step between adjacent grid levels (same units as oracle price) */
  gridStep:     Number(process.env.GRID_STEP    ?? 1.0),
  /** Base order size (in contracts, 6-decimal scaled) */
  baseSize:     Number(process.env.BASE_SIZE     ?? 1.0),
  /** Margin per order (USDC, 6-decimal scaled) */
  baseMargin:   Number(process.env.BASE_MARGIN   ?? 20.0),
  /** Maximum leverage (<=10) used to bound margin when scaling up */
  maxLeverage:  Number(process.env.MAX_LEVERAGE  ?? 4),

  // ── Martingale parameters ─────────────────────────────────────────────────
  /** Multiplier applied to size/margin after a losing close */
  martingaleMult:     Number(process.env.MARTINGALE_MULT      ?? 2.0),
  /** Reset to base size after this many consecutive wins */
  martingaleMaxLevel: Number(process.env.MARTINGALE_MAX_LEVEL ?? 4),

  // ── Timing ────────────────────────────────────────────────────────────────
  /** How often the bot polls for fills and refreshes grid (ms) */
  pollInterval: Number(process.env.POLL_INTERVAL ?? 5000),

  // ── Price decimals (must match contract pxDecimals) ───────────────────────
  pxDecimals: Number(process.env.PX_DECIMALS ?? 6),
} as const;
