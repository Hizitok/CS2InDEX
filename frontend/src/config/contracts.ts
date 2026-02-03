// Contract addresses - Update these after deployment
export const CONTRACTS = {
  VAULT: '0x...' as `0x${string}`,
  FACTORY: '0x...' as `0x${string}`,
  LIQUIDATION_ENGINE: '0x...' as `0x${string}`,
  ADL_ENGINE: '0x...' as `0x${string}`,
  USDC: '0x...' as `0x${string}`,
} as const;

// Contract ABIs
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
    inputs: [{ name: 'user', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'user', type: 'address' }],
    name: 'availableBalance',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'user', type: 'address' }],
    name: 'getUserBalanceInfo',
    outputs: [
      { name: 'total', type: 'uint256' },
      { name: 'locked', type: 'uint256' },
      { name: 'available', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

export const POOL_ABI = [
  {
    inputs: [
      {
        components: [
          { name: 'isSell', type: 'bool' },
          { name: 'oType', type: 'uint8' },
          { name: 'size', type: 'uint256' },
          { name: 'priceX100', type: 'uint256' },
          { name: 'margin', type: 'uint256' },
        ],
        name: 'pOrder',
        type: 'tuple',
      },
    ],
    name: 'newOrder',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'orderId', type: 'uint256' },
      {
        components: [
          { name: 'isSell', type: 'bool' },
          { name: 'oType', type: 'uint8' },
          { name: 'size', type: 'uint256' },
          { name: 'priceX100', type: 'uint256' },
          { name: 'margin', type: 'uint256' },
        ],
        name: 'pOrder',
        type: 'tuple',
      },
    ],
    name: 'closePosition',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [{ name: 'orderId', type: 'uint256' }],
    name: 'cancelOrder',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getLastPrice',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getPoolInfo',
    outputs: [
      { name: 'lastPriceX100', type: 'uint256' },
      { name: 'oraclePriceX100', type: 'uint256' },
      { name: 'feeCollected', type: 'uint256' },
      { name: 'askMin', type: 'uint256' },
      { name: 'bidMax', type: 'uint256' },
    ],
    stateMutability: 'view',

    type: 'function',
  },
  {
    inputs: [],
    name: 'getOrderbookInfo',
    outputs: [
      { name: 'lastPrice', type: 'uint256' },
      { name: 'askPrice', type: 'uint256' },
      { name: 'bidPrice', type: 'uint256' },
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
] as const;

export const FACTORY_ABI = [
  {
    inputs: [{ name: 'itemName', type: 'string' }],
    name: 'getPool',
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'itemName', type: 'string' }],
    name: 'getPoolInfo',
    outputs: [
      {
        components: [
          { name: 'poolAddress', type: 'address' },
          { name: 'oracle', type: 'address' },
          { name: 'positionNFT', type: 'address' },
          { name: 'itemName', type: 'string' },
          { name: 'deployedAt', type: 'uint256' },
          { name: 'active', type: 'bool' },
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
] as const;

export const INDEX_ORACLE_ABI = [
  {
    inputs: [{ name: 'pool', type: 'address' }],
    name: 'calculateFundingRate',
    outputs: [
      { name: 'fundingRate', type: 'int256' },
      { name: 'avgPremiumIndex', type: 'int256' },
      { name: 'interestRate', type: 'int256' },
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
      {
        name: 'positions',
        type: 'tuple[]',
        components: [
          { name: 'pool', type: 'address' },
          { name: 'positionID', type: 'uint256' },
          { name: 'status', type: 'uint8' },
          { name: 'isShort', type: 'bool' },
          { name: 'openMargin', type: 'uint256' },
          { name: 'pendingSize', type: 'uint256' },
          { name: 'openSize', type: 'uint256' },
          { name: 'closeSize', type: 'uint256' },
          { name: 'openAmount', type: 'uint256' },
          { name: 'closeAmount', type: 'uint256' },
        ],
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
] as const;
