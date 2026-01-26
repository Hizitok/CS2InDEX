# CS2InDEX Frontend

Modern, responsive web interface for the CS2InDEX decentralized perpetual trading platform.

## Features

- 🎯 **Trading Interface** - Open long/short positions with up to 6x leverage
- 💼 **Vault Management** - Deposit/withdraw USDC collateral
- 📊 **Position Management** - View and close open positions as NFTs
- 📈 **Market Overview** - Real-time price feeds and order book data
- 🔗 **Wallet Integration** - RainbowKit with support for multiple wallets
- ⚡ **Real-time Updates** - Automatic data refreshing
- 📱 **Responsive Design** - Works on desktop and mobile

## Tech Stack

- **Framework**: Next.js 14 (App Router)
- **Language**: TypeScript
- **Web3**: Wagmi v2 + Viem v2 + RainbowKit v2
- **Styling**: TailwindCSS
- **State**: React Query + Zustand
- **Icons**: Lucide React
- **Notifications**: React Hot Toast

## Prerequisites

- Node.js 18+ and npm/yarn/pnpm
- MetaMask or another Web3 wallet
- Deployed CS2InDEX contracts (addresses needed)

## Installation

```bash
# Install dependencies
npm install

# or
yarn install

# or
pnpm install
```

## Configuration

1. Copy the environment variables:
```bash
cp .env.example .env.local
```

2. Update `.env.local` with your values:
```env
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=your_project_id
```

3. Update contract addresses in `src/config/contracts.ts`:
```typescript
export const CONTRACTS = {
  VAULT: '0x...',
  FACTORY: '0x...',
  LIQUIDATION_ENGINE: '0x...',
  ADL_ENGINE: '0x...',
  USDC: '0x...',
};
```

4. Update pool addresses in components:
   - `src/components/trading/TradingInterface.tsx`
   - `src/components/market/MarketOverview.tsx`

## Development

Run the development server:

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

## Building for Production

```bash
# Build
npm run build

# Start production server
npm run start
```

## Project Structure

```
frontend/
├── src/
│   ├── app/                    # Next.js app router
│   │   ├── layout.tsx         # Root layout with providers
│   │   ├── page.tsx           # Home page
│   │   ├── providers.tsx      # Web3 providers
│   │   └── globals.css        # Global styles
│   ├── components/            # React components
│   │   ├── layout/           # Header, footer
│   │   ├── trading/          # Trading interface
│   │   ├── positions/        # Position management
│   │   ├── vault/            # Vault interactions
│   │   └── market/           # Market overview
│   └── config/               # Configuration
│       ├── contracts.ts      # ABIs and addresses
│       └── wagmi.ts          # Wagmi configuration
├── public/                   # Static assets
├── package.json
├── tsconfig.json
├── tailwind.config.js
└── next.config.js
```

## Key Components

### Trading Interface (`components/trading/TradingInterface.tsx`)
- Open long/short positions
- Limit and market orders
- Leverage calculation
- Real-time validation

### Positions List (`components/positions/PositionsList.tsx`)
- View all open positions
- Close positions
- Real-time PnL tracking
- Position status monitoring

### Vault Balance (`components/vault/VaultBalance.tsx`)
- Deposit USDC to vault
- Withdraw available balance
- View locked/available amounts
- USDC approval flow

### Market Overview (`components/market/MarketOverview.tsx`)
- Live price feeds
- Order book spreads
- Multiple markets

## Usage Guide

### 1. Connect Wallet
Click "Connect Wallet" in the header and select your wallet provider.

### 2. Deposit Collateral
1. Navigate to "Vault Balance"
2. Enter USDC amount
3. Click "Approve USDC" (first time only)
4. Click "Deposit"
5. Confirm transaction

### 3. Open Position
1. Select CS2 item (e.g., AK47-Redline)
2. Choose Long or Short
3. Select order type (Limit/Market)
4. Enter size and price
5. Enter margin (collateral)
6. Check leverage (max 6x)
7. Click "Open Position"

### 4. Manage Positions
1. View open positions in "Your Positions"
2. Click "Close" on a position
3. Enter close price
4. Confirm to close

### 5. Withdraw Funds
1. Navigate to "Vault Balance"
2. Click "Withdraw" tab
3. Enter amount (max = available balance)
4. Click "Withdraw"

## Features in Detail

### Order Types
- **Limit**: Specify exact entry price
- **Market**: Execute at best available price
- **IOC**: Immediate or cancel
- **FOK**: Fill or kill

### Position States
- **Pending Open**: Order placed, waiting for match
- **Open**: Position active
- **Pending Close**: Close order placed
- **Force Close**: Liquidated
- **Closed**: Position settled

### Leverage
- Maximum: 6x
- Calculated as: `(Size × Price) / Margin`
- Automatically validated before submission

### Safety Features
- Real-time leverage validation
- Balance checks before transactions
- Transaction confirmation toasts
- Error handling and user feedback

## Styling

The app uses TailwindCSS with a custom dark theme:

- **Primary**: Blue gradient (#0ea5e9)
- **Success**: Green (#10b981)
- **Error**: Red (#ef4444)
- **Background**: Dark gray gradients

Custom classes in `globals.css`:
- `.btn-primary` - Primary button
- `.btn-secondary` - Secondary button
- `.card` - Card container
- `.input` - Form input
- `.label` - Form label

## Web3 Integration

### Wagmi Hooks Used
- `useAccount` - Current connected account
- `useReadContract` - Read contract state
- `useWriteContract` - Write to contracts
- `useWaitForTransactionReceipt` - Wait for tx confirmation

### Contract Interactions
- Vault: deposit, withdraw, balanceOf
- Pool: newOrder, closePosition, cancelOrder
- ERC20: approve, balanceOf, allowance
- PositionNFT: getPositionsByOwner

## Error Handling

All contract interactions include:
- Try-catch blocks
- User-friendly error messages
- Toast notifications
- Loading states

## Performance Optimizations

- React Query caching
- Automatic data refetching (5-10s intervals)
- Conditional rendering
- Lazy loading
- Optimized re-renders

## Security Considerations

- No private keys stored
- All transactions require user approval
- Input validation
- Safe math operations (viem)
- Address checksums

## Browser Support

- Chrome/Edge (recommended)
- Firefox
- Brave
- Safari (limited)

## Mobile Support

- Responsive design
- Touch-friendly interfaces
- WalletConnect for mobile wallets

## Troubleshooting

### Wallet Not Connecting
- Check MetaMask is installed
- Ensure correct network (Sepolia/Mainnet)
- Try refreshing the page

### Transaction Failing
- Check sufficient USDC balance
- Verify vault has USDC approval
- Ensure gas fees are available
- Check leverage is not > 6x

### Data Not Loading
- Verify contract addresses are correct
- Check RPC endpoint is working
- Look for console errors
- Try refreshing the page

## Development Tips

### Adding New Pools
1. Deploy pool contracts
2. Update `POOLS` array in components
3. Update `CONTRACTS` in config

### Customizing Theme
Edit `tailwind.config.js` colors and `globals.css` styles.

### Adding Features
- Use existing hooks and patterns
- Follow component structure
- Add proper TypeScript types
- Include error handling

## Contributing

1. Fork the repository
2. Create feature branch
3. Make changes
4. Test thoroughly
5. Submit pull request

## License

MIT

## Support

- Documentation: [link]
- Discord: [link]
- Twitter: [link]

## Acknowledgments

Built with:
- Next.js by Vercel
- Wagmi by Wevm
- RainbowKit by Rainbow
- TailwindCSS by Tailwind Labs
