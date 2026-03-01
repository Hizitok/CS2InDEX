// Contract addresses - Update these after deployment
// deploy.sh auto-updates FACTORY, VAULT, USDC, ROUTER, NFT, POOL after running
export const CONTRACTS = {
  VAULT:   '0xe0c45Ec696231DF891d4A4eA34Bd3F132b1CA5B2' as `0x${string}`,
  FACTORY: '0xFeC51Ce8694f04AB585D1b00A67cCb8c2f9bb3e3' as `0x${string}`,
  USDC:    '0xa260796BcDE227d2460A21dbCc3D116cafc9A3D6' as `0x${string}`,
  ROUTER:  '0xE13056d8d0b00000468e8aff83bBaff9Bb50340a' as `0x${string}`,
  NFT:     '0x4162e92431f212b845dEAC2Af96DD0206dc5Ba60' as `0x${string}`,
  // Primary pool (CS2-Global-Index) — chain 1301 (unichain-sepolia)
  POOL:    '0x8d7f83eD4849Ded78E727AA4b954c4a11f0830Df' as `0x${string}`,
} as const;

// Price decimals (aligned with USDC = 6)
export const PX_DECIMALS = 6;

// orderType enum values: none=0, Market=1, Limit=2, FOK=3, IOC=4
export const ORDER_TYPE = {
  None: 0,
  Market: 1,
  Limit: 2,
  FOK: 3,
  IOC: 4,
} as const;

// Fee rates
export const MAKER_FEE = 0.003; // 0.3%
export const TAKER_FEE = 0.005; // 0.5%

// ========== Contract ABIs (aligned with Solidity interfaces) ==========

export const VAULT_ABI = [
  {
    inputs: [{ name: 'amount', type: 'uint256' }],
    name: 'deposit',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [{ name: 'amount', type: 'uint256' }],
    name: 'withdraw',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'withdrawTo',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [{ name: 'user', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'supportedToken',
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getVaultStats',
    outputs: [
      { name: '_supportedToken', type: 'address' },
      { name: '_totalAmount', type: 'uint256' },
      { name: '_actualBalance', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

// PoolOrder: { isSell: bool, oType: uint8, size: uint256, price: uint256 }
const POOL_ORDER_COMPONENTS = [
  { name: 'isSell', type: 'bool' },
  { name: 'oType', type: 'uint8' },
  { name: 'size', type: 'uint256' },
  { name: 'price', type: 'uint256' },
] as const;

export const POOL_ABI = [
  // newOrder(uint256 margin, PoolOrder pOrder) => OrderId
  {
    inputs: [
      { name: 'margin', type: 'uint256' },
      { components: POOL_ORDER_COMPONENTS, name: 'pOrder', type: 'tuple' },
    ],
    name: 'newOrder',
    outputs: [{ name: 'newPosId', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  // closePosition(OrderId orderId, PoolOrder pOrder) => OrderId
  {
    inputs: [
      { name: 'orderId', type: 'uint256' },
      { components: POOL_ORDER_COMPONENTS, name: 'pOrder', type: 'tuple' },
    ],
    name: 'closePosition',
    outputs: [{ name: 'newPosId', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  // cancelOrder(OrderId orderId) => bool
  {
    inputs: [{ name: 'orderId', type: 'uint256' }],
    name: 'cancelOrder',
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  // settlePnL(OrderId orderId)
  {
    inputs: [{ name: 'orderId', type: 'uint256' }],
    name: 'settlePnL',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  // getLastPrice() => uint256
  {
    inputs: [],
    name: 'getLastPrice',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  // getOrderbookInfo() => (lastPrice, ask1Price, bid1Price)
  {
    inputs: [],
    name: 'getOrderbookInfo',
    outputs: [
      { name: '_lastPriceX100', type: 'uint256' },
      { name: '_ask1Price', type: 'uint256' },
      { name: '_bid1Price', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'fundingIdx',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'maxLeverage',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'oraclePrice',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'oracle',
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'vault',
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'positionNFT',
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'engine',
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  // getOrderPrice(uint256 orderId) => uint256 — limit price stored in OBPx for a pending order
  {
    inputs: [{ name: 'orderId', type: 'uint256' }],
    name: 'getOrderPrice',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  // getDepth(uint256 nLevels) => (askPrices, askSizes, bidPrices, bidSizes)
  {
    inputs: [{ name: 'nLevels', type: 'uint256' }],
    name: 'getDepth',
    outputs: [
      { name: 'askPrices', type: 'uint256[]' },
      { name: 'askSizes',  type: 'uint256[]' },
      { name: 'bidPrices', type: 'uint256[]' },
      { name: 'bidSizes',  type: 'uint256[]' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  // Events
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'orderId', type: 'uint256' },
      { indexed: true, name: 'trader', type: 'address' },
      { indexed: false, name: 'isSell', type: 'bool' },
      { indexed: false, name: 'size', type: 'uint256' },
      { indexed: false, name: 'price', type: 'uint256' },
    ],
    name: 'OrderCreated',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'orderId', type: 'uint256' },
      { indexed: true, name: 'matchedOrderId', type: 'uint256' },
      { indexed: false, name: 'size', type: 'uint256' },
      { indexed: false, name: 'price', type: 'uint256' },
    ],
    name: 'OrderMatched',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'orderId', type: 'uint256' },
      { indexed: true, name: 'trader', type: 'address' },
    ],
    name: 'OrderCancelled',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'orderId', type: 'uint256' },
      { indexed: true, name: 'trader', type: 'address' },
      { indexed: false, name: 'pnl', type: 'int256' },
    ],
    name: 'PnLSettled',
    type: 'event',
  },
] as const;

export const FACTORY_ABI = [
  {
    inputs: [{ name: 'pool', type: 'address' }],
    name: 'getPoolInfo',
    outputs: [
      {
        components: [
          { name: 'factory', type: 'address' },
          { name: 'pool', type: 'address' },
          { name: 'engine', type: 'address' },
          { name: 'deployedAt', type: 'uint256' },
          { name: 'itemName', type: 'string' },
        ],
        name: '',
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getAllPools',
    outputs: [{ name: '', type: 'address[]' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'poolCount',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'pool', type: 'address' }],
    name: 'isValidPool',
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'vault',
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'oracle',
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'nft',
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'pool', type: 'address' }],
    name: 'getPoolStats',
    outputs: [
      {
        components: [
          { name: 'factory', type: 'address' },
          { name: 'pool', type: 'address' },
          { name: 'engine', type: 'address' },
          { name: 'deployedAt', type: 'uint256' },
          { name: 'itemName', type: 'string' },
        ],
        name: 'info',
        type: 'tuple',
      },
      { name: 'lastPrice', type: 'uint256' },
      { name: 'oraclePrice_', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

export const ERC20_ABI = [
  {
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'approve',
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    name: 'allowance',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'account', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'decimals',
    outputs: [{ name: '', type: 'uint8' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'mint',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
] as const;

// calculateFundingRate returns (avgVTWAPDiff, interestRate, fundingRate) — all int128
export const INDEX_ORACLE_ABI = [
  {
    inputs: [{ name: 'pool', type: 'address' }],
    name: 'calculateFundingRate',
    outputs: [
      { name: 'avgVTWAPDiff', type: 'int128' },
      { name: 'interestRate', type: 'int128' },
      { name: 'fundingRate', type: 'int128' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'pool', type: 'address' }],
    name: 'oraclePrice',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'pool', type: 'address' }],
    name: 'updateTime',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

// Position struct fields matching OrderTypes.sol
const POSITION_COMPONENTS = [
  { name: 'isShort', type: 'bool' },
  { name: 'status', type: 'uint8' },
  { name: 'openMargin', type: 'uint256' },
  { name: 'pendingSize', type: 'uint128' },
  { name: 'openSize', type: 'uint128' },
  { name: 'closeSize', type: 'uint128' },
  { name: 'openAmount', type: 'uint128' },
  { name: 'closeAmount', type: 'uint128' },
  { name: 'openFundingIdx', type: 'uint128' },
  { name: 'closeFundingIdx', type: 'uint128' },
] as const;

// Router ABI — single entry-point for all trading operations
export const ROUTER_ABI = [
  // getPortfolio(address user) returns PositionView[]
  // PositionView { pool, posId, pos, oraclePrice }
  {
    inputs: [{ name: 'user', type: 'address' }],
    name: 'getPortfolio',
    outputs: [
      {
        components: [
          { name: 'pool',        type: 'address' },
          { name: 'posId',       type: 'uint256' },
          { components: POSITION_COMPONENTS, name: 'pos', type: 'tuple' },
          { name: 'oraclePrice', type: 'uint256' },
        ],
        name: '',
        type: 'tuple[]',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

export const POSITION_NFT_ABI = [
  {
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    name: 'ownerOf',
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'owner', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'owner', type: 'address' }],
    name: 'getPositionsByOwner',
    outputs: [
      { name: 'tokenIds', type: 'uint256[]' },
      { name: 'positions', type: 'tuple[]', components: POSITION_COMPONENTS },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'oID', type: 'uint256' }],
    name: 'getPosition',
    outputs: [
      { name: '', type: 'tuple', components: POSITION_COMPONENTS },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'orderId', type: 'uint256' }],
    name: 'getOpenTick',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'totalSupply',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;
