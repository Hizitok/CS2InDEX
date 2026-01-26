# CS2InDEX Frontend Deployment Guide

Complete guide for deploying the CS2InDEX frontend to production.

## Prerequisites

- Deployed smart contracts with addresses
- WalletConnect Project ID
- Vercel/Netlify account (for hosting)
- Domain name (optional)

## Step 1: Configure Environment

1. **Get WalletConnect Project ID**
   - Visit [cloud.walletconnect.com](https://cloud.walletconnect.com/)
   - Create a new project
   - Copy the Project ID

2. **Update Environment Variables**
   ```bash
   cp .env.example .env.local
   ```

   Edit `.env.local`:
   ```env
   NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=your_actual_project_id
   ```

3. **Update Contract Addresses**

   Edit `src/config/contracts.ts`:
   ```typescript
   export const CONTRACTS = {
     VAULT: '0xYourVaultAddress',
     FACTORY: '0xYourFactoryAddress',
     LIQUIDATION_ENGINE: '0xYourLiquidationEngineAddress',
     ADL_ENGINE: '0xYourADLEngineAddress',
     USDC: '0xUSDCAddress', // 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 on mainnet
   };
   ```

4. **Update Pool Addresses**

   Get pool addresses from factory and update:
   - `src/components/trading/TradingInterface.tsx`
   - `src/components/market/MarketOverview.tsx`
   - `src/components/positions/PositionsList.tsx`

   ```typescript
   const ITEMS = [
     { name: 'AK47-Redline', pool: '0xPoolAddress1' },
     { name: 'AWP-Dragon Lore', pool: '0xPoolAddress2' },
     { name: 'M4A4-Howl', pool: '0xPoolAddress3' },
   ];
   ```

## Step 2: Test Locally

```bash
# Install dependencies
npm install

# Run development server
npm run dev

# Test all features:
# - Wallet connection
# - Deposit to vault
# - Open position
# - Close position
# - Withdraw from vault
```

## Step 3: Build for Production

```bash
# Create production build
npm run build

# Test production build locally
npm run start
```

Fix any build errors before deploying.

## Step 4: Deploy to Vercel

### Option A: GitHub Integration (Recommended)

1. **Push to GitHub**
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   git remote add origin https://github.com/yourusername/cs2index-frontend.git
   git push -u origin main
   ```

2. **Deploy on Vercel**
   - Visit [vercel.com](https://vercel.com)
   - Click "New Project"
   - Import your GitHub repository
   - Configure project:
     - Framework Preset: Next.js
     - Root Directory: ./
     - Build Command: `npm run build`
     - Output Directory: (leave default)
   - Add Environment Variables:
     ```
     NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=your_project_id
     ```
   - Click "Deploy"

3. **Automatic Deployments**
   - Every push to `main` triggers a new deployment
   - Preview deployments for pull requests

### Option B: Vercel CLI

```bash
# Install Vercel CLI
npm i -g vercel

# Login
vercel login

# Deploy
vercel

# Deploy to production
vercel --prod
```

## Step 5: Deploy to Netlify

### Via Git Integration

1. **Push to GitHub** (if not done already)

2. **Deploy on Netlify**
   - Visit [netlify.com](https://netlify.com)
   - Click "New site from Git"
   - Connect to GitHub
   - Select repository
   - Configure:
     - Build command: `npm run build`
     - Publish directory: `.next`
   - Add Environment Variables
   - Click "Deploy site"

### Via Netlify CLI

```bash
# Install Netlify CLI
npm install -g netlify-cli

# Login
netlify login

# Initialize
netlify init

# Deploy
netlify deploy --prod
```

## Step 6: Custom Domain

### Vercel

1. Go to project settings
2. Navigate to "Domains"
3. Add your domain
4. Configure DNS:
   - Type: CNAME
   - Name: www (or @)
   - Value: cname.vercel-dns.com

### Netlify

1. Go to "Domain settings"
2. Click "Add custom domain"
3. Follow DNS configuration instructions

## Step 7: Configure CORS

If using a separate API, configure CORS:

`next.config.js`:
```javascript
module.exports = {
  async headers() {
    return [
      {
        source: '/api/:path*',
        headers: [
          { key: 'Access-Control-Allow-Origin', value: 'https://yourdomain.com' },
        ],
      },
    ];
  },
};
```

## Step 8: Set Up Analytics

### Google Analytics

1. Create GA4 property
2. Add tracking ID to `.env.local`:
   ```env
   NEXT_PUBLIC_GA_ID=G-XXXXXXXXXX
   ```
3. Install:
   ```bash
   npm install @next/third-parties
   ```
4. Add to layout:
   ```typescript
   import { GoogleAnalytics } from '@next/third-parties/google'

   export default function RootLayout({ children }) {
     return (
       <html>
         <body>{children}</body>
         <GoogleAnalytics gaId="G-XXXXXXXXXX" />
       </html>
     )
   }
   ```

## Step 9: Performance Optimization

### Image Optimization

Use Next.js Image component:
```typescript
import Image from 'next/image'

<Image
  src="/cs2-item.png"
  width={200}
  height={200}
  alt="CS2 Item"
/>
```

### Code Splitting

Already handled by Next.js, but you can optimize imports:
```typescript
import dynamic from 'next/dynamic'

const HeavyComponent = dynamic(() => import('./HeavyComponent'))
```

### Caching

Configure in `next.config.js`:
```javascript
module.exports = {
  async headers() {
    return [
      {
        source: '/static/:path*',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=31536000, immutable',
          },
        ],
      },
    ];
  },
};
```

## Step 10: Security Headers

Add security headers in `next.config.js`:
```javascript
module.exports = {
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          {
            key: 'X-DNS-Prefetch-Control',
            value: 'on'
          },
          {
            key: 'Strict-Transport-Security',
            value: 'max-age=63072000; includeSubDomains; preload'
          },
          {
            key: 'X-Frame-Options',
            value: 'SAMEORIGIN'
          },
          {
            key: 'X-Content-Type-Options',
            value: 'nosniff'
          },
          {
            key: 'Referrer-Policy',
            value: 'origin-when-cross-origin'
          }
        ]
      }
    ]
  }
}
```

## Step 11: Monitoring

### Error Tracking with Sentry

```bash
npm install @sentry/nextjs
```

Configure `sentry.client.config.js`:
```javascript
import * as Sentry from '@sentry/nextjs';

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  tracesSampleRate: 0.1,
});
```

### Uptime Monitoring

Use services like:
- UptimeRobot
- Pingdom
- StatusCake

## Step 12: CI/CD Pipeline

### GitHub Actions

Create `.github/workflows/deploy.yml`:
```yaml
name: Deploy to Production

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test

      - name: Build
        run: npm run build
        env:
          NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID: ${{ secrets.WALLETCONNECT_PROJECT_ID }}

      - name: Deploy to Vercel
        uses: amondnet/vercel-action@v20
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
          vercel-args: '--prod'
```

## Production Checklist

- [ ] All contract addresses updated
- [ ] WalletConnect Project ID configured
- [ ] Environment variables set
- [ ] Build successful
- [ ] Wallet connection works
- [ ] Deposits work
- [ ] Trading works
- [ ] Withdrawals work
- [ ] Custom domain configured
- [ ] SSL certificate active
- [ ] Analytics tracking
- [ ] Error monitoring
- [ ] Performance optimized
- [ ] Security headers configured
- [ ] CORS configured (if needed)
- [ ] Backup and recovery plan

## Troubleshooting

### Build Failures

**Error**: Module not found
```bash
# Clear cache and reinstall
rm -rf node_modules .next
npm install
npm run build
```

### Environment Variables Not Working

- Must start with `NEXT_PUBLIC_` for client-side
- Restart dev server after changes
- Redeploy after updating

### Wallet Not Connecting

- Check WalletConnect Project ID
- Verify network configuration
- Check browser console for errors

### Contract Interactions Failing

- Verify contract addresses are correct
- Check network (mainnet/testnet)
- Ensure contracts are verified on Etherscan
- Check gas settings

## Rollback Procedure

### Vercel
1. Go to Deployments
2. Find last working deployment
3. Click "..." → "Promote to Production"

### Netlify
1. Go to Deploys
2. Find last working deploy
3. Click "Publish deploy"

## Maintenance

### Regular Updates

```bash
# Check for updates
npm outdated

# Update dependencies
npm update

# Update Next.js
npm install next@latest react@latest react-dom@latest

# Update Wagmi
npm install wagmi@latest viem@latest @rainbow-me/rainbowkit@latest
```

### Monitoring Checklist

Weekly:
- Check error rates
- Monitor performance metrics
- Review analytics
- Test key user flows

Monthly:
- Update dependencies
- Security audit
- Performance optimization
- Review user feedback

## Support

- GitHub Issues: [link]
- Discord: [link]
- Email: support@cs2index.com

## Additional Resources

- [Next.js Deployment Docs](https://nextjs.org/docs/deployment)
- [Vercel Docs](https://vercel.com/docs)
- [Netlify Docs](https://docs.netlify.com/)
- [Wagmi Docs](https://wagmi.sh/)
