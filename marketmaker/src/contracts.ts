// Minimal ABIs — only what the market maker needs
export const POOL_ABI = [
  // newOrder(uint256 margin, PoolOrder pOrder) => uint256 posId
  {
    inputs: [
      { name: 'margin', type: 'uint256' },
      {
        components: [
          { name: 'isSell', type: 'bool' },
          { name: 'oType',  type: 'uint8' },
          { name: 'size',   type: 'uint256' },
          { name: 'price',  type: 'uint256' },
        ],
        name: 'pOrder',
        type: 'tuple',
      },
    ],
    name: 'newOrder',
    outputs: [{ name: 'newPosId', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  // closePosition(uint256 orderId, PoolOrder pOrder) => uint256
  {
    inputs: [
      { name: 'orderId', type: 'uint256' },
      {
        components: [
          { name: 'isSell', type: 'bool' },
          { name: 'oType',  type: 'uint8' },
          { name: 'size',   type: 'uint256' },
          { name: 'price',  type: 'uint256' },
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
  // cancelOrder(uint256 orderId) => bool
  {
    inputs: [{ name: 'orderId', type: 'uint256' }],
    name: 'cancelOrder',
    outputs: [{ name: '', type: 'bool' }],
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
  // oraclePrice() => uint256
  {
    inputs: [],
    name: 'oraclePrice',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

// positionNFT ABI — only getPosition
const POSITION_COMPONENTS = [
  { name: 'positionID',     type: 'uint256' },
  { name: 'pool',           type: 'address' },
  { name: 'isShort',        type: 'bool'    },
  { name: 'status',         type: 'uint8'   },
  { name: 'openMargin',     type: 'uint256' },
  { name: 'pendingSize',    type: 'uint256' },
  { name: 'openSize',       type: 'uint256' },
  { name: 'closeSize',      type: 'uint256' },
  { name: 'openAmount',     type: 'uint256' },
  { name: 'closeAmount',    type: 'uint256' },
  { name: 'openFundingIdx', type: 'uint256' },
  { name: 'closeFundingIdx',type: 'uint256' },
] as const;

export const POSITION_NFT_ABI = [
  {
    inputs: [{ name: 'oID', type: 'uint256' }],
    name: 'getPosition',
    outputs: [{ name: '', type: 'tuple', components: POSITION_COMPONENTS }],
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
] as const;

export const VAULT_ABI = [
  {
    inputs: [{ name: 'amount', type: 'uint256' }],
    name: 'deposit',
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
] as const;

export const ERC20_ABI = [
  {
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount',  type: 'uint256' },
    ],
    name: 'approve',
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'nonpayable',
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
    inputs: [
      { name: 'owner',   type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    name: 'allowance',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  // MockUSDC testnet faucet — no access control
  {
    inputs: [
      { name: 'to',     type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'mint',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
] as const;

// orderType enum values matching OrderTypes.sol
export const ORDER_TYPE = { Market: 1, Limit: 2 } as const;

// posStatus enum values — must match OrderTypes.sol:
//   enum posStatus { none=0, pendingOpen=1, open=2, pendingClose=3, liquidating=4, closed=5, settled=6 }
export const POS_STATUS = {
  none:         0,
  pendingOpen:  1,
  open:         2,
  pendingClose: 3,
  liquidating:  4,
  closed:       5,
  settled:      6,
} as const;
