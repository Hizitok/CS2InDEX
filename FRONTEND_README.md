# CS2InDEX 前端开发文档
# 0 :most important 请使用中文交互！！！(务必遵守)
## 📖 项目概述

CS2InDEX 是一个基于以太坊的去中心化 CS2 皮肤永续合约交易平台。用户可以通过钱包直接与智能合约交互，无需中心化后端服务。

### 核心特性
- ✅ 去中心化订单簿
- ✅ 永续合约交易（支持多空双向）
- ✅ 自动资金费率计算
- ✅ NFT 仓位管理
- ✅ 实时订单撮合

---

## 🏗️ 系统架构

```
前端 (React/Vue/Next.js)
    ↓
钱包 (MetaMask/WalletConnect)
    ↓
智能合约层
    ├─ Pool (交易池)
    ├─ Vault (资金管理)
    ├─ Position (仓位NFT)
    └─ IndexOracle (价格预言机)
```

---

## 📦 合约地址（部署后填写）

```typescript
// src/config/contracts.ts
export const CONTRACTS = {
  // 测试网地址
  sepolia: {
    pool: '0x...',           // Pool 合约地址
    vault: '0x...',          // Vault 合约地址
    position: '0x...',       // Position NFT 合约地址
    oracle: '0x...',         // IndexOracle 合约地址
    usdt: '0x...',           // USDT 测试币地址
  },
  // 主网地址
  mainnet: {
    pool: '0x...',
    vault: '0x...',
    position: '0x...',
    oracle: '0x...',
    usdt: '0x6B175474E89094C44Da98b954EedeAC495271d0F', // DAI on mainnet
  }
};
```

---

## 🚀 快速开始

### 1. 安装依赖

```bash
npm install ethers@6 wagmi viem @rainbow-me/rainbowkit
# 或
npm install @web3-onboard/core @web3-onboard/injected-wallets
```

### 2. 配置钱包连接

#### 使用 RainbowKit + wagmi (推荐)

```typescript
// src/wagmi.config.ts
import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { sepolia, mainnet } from 'wagmi/chains';

export const config = getDefaultConfig({
  appName: 'CS2InDEX',
  projectId: 'YOUR_WALLETCONNECT_PROJECT_ID', // 从 https://cloud.walletconnect.com 获取
  chains: [sepolia, mainnet],
  ssr: true, // 如果使用 Next.js
});
```

```tsx
// src/app/layout.tsx (Next.js) 或 src/main.tsx (Vite)
import { WagmiProvider } from 'wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { RainbowKitProvider } from '@rainbow-me/rainbowkit';
import { config } from './wagmi.config';
import '@rainbow-me/rainbowkit/styles.css';

const queryClient = new QueryClient();

export default function App({ children }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider>
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
```

### 3. 获取 ABI 文件

ABI 文件位于编译输出目录：

```bash
# 使用 Foundry 编译
forge build

# ABI 文件位置
out/Pool.sol/Pool.json
out/Vault.sol/Vault.json
out/Position.sol/Position.json
out/IndexOracle.sol/IndexOracle.json
```

将 ABI 复制到前端项目：

```bash
mkdir -p frontend/src/abis
cp out/Pool.sol/Pool.json frontend/src/abis/
cp out/Vault.sol/Vault.json frontend/src/abis/
cp out/Position.sol/Position.json frontend/src/abis/
cp out/IndexOracle.sol/IndexOracle.json frontend/src/abis/
```

---

## 📚 核心功能实现

### 1. 读取合约数据（不需要钱包）

#### 使用 wagmi hooks

```typescript
// src/hooks/usePool.ts
import { useReadContract } from 'wagmi';
import PoolABI from '@/abis/Pool.json';
import { CONTRACTS } from '@/config/contracts';

// 获取订单簿信息
export function useOrderbook() {
  const { data, isLoading, refetch } = useReadContract({
    address: CONTRACTS.sepolia.pool,
    abi: PoolABI.abi,
    functionName: 'getOrderbookInfo',
  });

  return {
    lastPrice: data?.[0],     // 最新成交价
    askPrice: data?.[1],      // 卖一价
    bidPrice: data?.[2],      // 买一价
    isLoading,
    refetch
  };
}

// 获取最新价格
export function useLastPrice() {
  const { data } = useReadContract({
    address: CONTRACTS.sepolia.pool,
    abi: PoolABI.abi,
    functionName: 'getLastPrice',
  });

  return {
    price: data,
  };
}

// 获取资金费率信息
export function useFundingRate() {
  const { data } = useReadContract({
    address: CONTRACTS.sepolia.pool,
    abi: PoolABI.abi,
    functionName: 'fundingIdx',
  });

  return {
    fundingIdx: data,
  };
}
```

#### 使用 ethers.js (传统方式)

```typescript
// src/lib/contracts.ts
import { ethers } from 'ethers';
import PoolABI from '@/abis/Pool.json';
import { CONTRACTS } from '@/config/contracts';

// 获取只读 Provider
export const getProvider = () => {
  if (typeof window !== 'undefined' && window.ethereum) {
    return new ethers.BrowserProvider(window.ethereum);
  }
  // 回退到公共 RPC
  return new ethers.JsonRpcProvider('https://rpc.ankr.com/eth_sepolia');
};

// 获取合约实例
export const getPoolContract = async (needSigner = false) => {
  const provider = getProvider();
  if (needSigner) {
    const signer = await provider.getSigner();
    return new ethers.Contract(CONTRACTS.sepolia.pool, PoolABI.abi, signer);
  }
  return new ethers.Contract(CONTRACTS.sepolia.pool, PoolABI.abi, provider);
};

// 示例：获取订单簿
export async function fetchOrderbook() {
  const pool = await getPoolContract(false);
  const [lastPrice, askPrice, bidPrice] = await pool.getOrderbookInfo();

  return {
    lastPrice: ethers.formatUnits(lastPrice, 18),
    askPrice: ethers.formatUnits(askPrice, 18),
    bidPrice: ethers.formatUnits(bidPrice, 18),
  };
}
```

### 2. 查询用户数据

```typescript
// src/hooks/useUserBalance.ts
import { useReadContract, useAccount } from 'wagmi';
import VaultABI from '@/abis/Vault.json';

export function useUserBalance() {
  const { address } = useAccount();

  const { data, isLoading } = useReadContract({
    address: CONTRACTS.sepolia.vault,
    abi: VaultABI.abi,
    functionName: 'balanceOf',
    args: [address],
    query: {
      enabled: !!address, // 只在有地址时查询
    }
  });

  return {
    balance: data,
    isLoading,
  };
}
```

```typescript
// src/hooks/useUserPositions.ts
import { useReadContract, useAccount } from 'wagmi';
import PositionABI from '@/abis/Position.json';

export function useUserPosition(orderId: bigint) {
  const { data, isLoading } = useReadContract({
    address: CONTRACTS.sepolia.position,
    abi: PositionABI.abi,
    functionName: 'getPosition',
    args: [orderId],
  });

  return {
    position: data ? {
      orderId: data.positionID,
      pool: data.pool,
      isShort: data.isShort,
      status: data.status,
      openSize: data.openSize,
      openAmount: data.openAmount,
      margin: data.openMargin,
      // ... 其他字段
    } : null,
    isLoading,
  };
}
```

### 3. 写入交易（需要钱包签名）

```typescript
// src/hooks/useCreateOrder.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseUnits } from 'viem';
import PoolABI from '@/abis/Pool.json';

export function useCreateOrder() {
  const {
    writeContract,
    data: hash,
    isPending,
    error
  } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const createOrder = async (params: {
    margin: string;      // "100" USDT
    isSell: boolean;     // true = 开空, false = 开多
    orderType: number;   // 1=Market, 2=Limit, 3=FOK, 4=IOC
    size: string;        // "10" 合约数量
    price: string;       // "1000" 价格 (Limit订单用)
  }) => {
    const order = {
      isSell: params.isSell,
      oType: params.orderType,
      size: parseUnits(params.size, 18),
      price: parseUnits(params.price, 18),
    };

    const marginAmount = parseUnits(params.margin, 6); // USDT 6位小数

    await writeContract({
      address: CONTRACTS.sepolia.pool,
      abi: PoolABI.abi,
      functionName: 'newOrder',
      args: [marginAmount, order],
    });
  };

  return {
    createOrder,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  };
}
```

```typescript
// src/hooks/useCancelOrder.ts
export function useCancelOrder() {
  const { writeContract, ...rest } = useWriteContract();

  const cancelOrder = (orderId: bigint) => {
    writeContract({
      address: CONTRACTS.sepolia.pool,
      abi: PoolABI.abi,
      functionName: 'cancelOrder',
      args: [orderId],
    });
  };

  return { cancelOrder, ...rest };
}
```

```typescript
// src/hooks/useClosePosition.ts
export function useClosePosition() {
  const { writeContract, ...rest } = useWriteContract();

  const closePosition = (
    orderId: bigint,
    size: string,
    price: string,
    isSell: boolean
  ) => {
    const order = {
      isSell,
      oType: 2, // Limit order
      size: parseUnits(size, 18),
      price: parseUnits(price, 18),
    };

    writeContract({
      address: CONTRACTS.sepolia.pool,
      abi: PoolABI.abi,
      functionName: 'closePosition',
      args: [orderId, order],
    });
  };

  return { closePosition, ...rest };
}
```

### 4. 组件使用示例

```tsx
// src/components/TradingPanel.tsx
import { useCreateOrder, useOrderbook } from '@/hooks';
import { useState } from 'react';

export function TradingPanel() {
  const [margin, setMargin] = useState('100');
  const [size, setSize] = useState('10');
  const [price, setPrice] = useState('');

  const { lastPrice, askPrice, bidPrice } = useOrderbook();
  const { createOrder, isPending, isSuccess } = useCreateOrder();

  const handleBuyMarket = async () => {
    await createOrder({
      margin,
      isSell: false,        // 买入 = 开多
      orderType: 1,         // 市价单
      size,
      price: '0',           // 市价单价格为0
    });
  };

  const handleSellLimit = async () => {
    await createOrder({
      margin,
      isSell: true,         // 卖出 = 开空
      orderType: 2,         // 限价单
      size,
      price,
    });
  };

  return (
    <div className="trading-panel">
      <h2>交易面板</h2>

      {/* 价格显示 */}
      <div className="prices">
        <p>最新价: {lastPrice?.toString()}</p>
        <p>买一价: {bidPrice?.toString()}</p>
        <p>卖一价: {askPrice?.toString()}</p>
      </div>

      {/* 交易表单 */}
      <div className="form">
        <input
          type="text"
          placeholder="保证金"
          value={margin}
          onChange={(e) => setMargin(e.target.value)}
        />
        <input
          type="text"
          placeholder="数量"
          value={size}
          onChange={(e) => setSize(e.target.value)}
        />
        <input
          type="text"
          placeholder="价格 (限价单)"
          value={price}
          onChange={(e) => setPrice(e.target.value)}
        />
      </div>

      {/* 交易按钮 */}
      <div className="actions">
        <button
          onClick={handleBuyMarket}
          disabled={isPending}
        >
          {isPending ? '处理中...' : '市价买入 (开多)'}
        </button>
        <button
          onClick={handleSellLimit}
          disabled={isPending}
        >
          {isPending ? '处理中...' : '限价卖出 (开空)'}
        </button>
      </div>

      {/* 交易结果 */}
      {isSuccess && (
        <div className="success">
          交易成功！
        </div>
      )}
    </div>
  );
}
```

---

## 🎧 事件监听

### 监听合约事件

```typescript
// src/hooks/useOrderEvents.ts
import { useWatchContractEvent } from 'wagmi';
import PoolABI from '@/abis/Pool.json';

export function useOrderEvents(onEvent: (event: any) => void) {
  // 监听 OrderCreated 事件
  useWatchContractEvent({
    address: CONTRACTS.sepolia.pool,
    abi: PoolABI.abi,
    eventName: 'OrderCreated',
    onLogs(logs) {
      logs.forEach(log => {
        onEvent({
          type: 'OrderCreated',
          orderId: log.args.orderId,
          trader: log.args.trader,
          isSell: log.args.isSell,
          size: log.args.size,
          price: log.args.price,
        });
      });
    },
  });

  // 监听 OrderMatched 事件
  useWatchContractEvent({
    address: CONTRACTS.sepolia.pool,
    abi: PoolABI.abi,
    eventName: 'OrderMatched',
    onLogs(logs) {
      logs.forEach(log => {
        onEvent({
          type: 'OrderMatched',
          orderId: log.args.orderId,
          matchedOrderId: log.args.matchedOrderId,
          size: log.args.size,
          price: log.args.price,
        });
      });
    },
  });
}
```

### 使用事件监听

```tsx
// src/components/RecentTrades.tsx
import { useState } from 'react';
import { useOrderEvents } from '@/hooks/useOrderEvents';

export function RecentTrades() {
  const [trades, setTrades] = useState([]);

  useOrderEvents((event) => {
    if (event.type === 'OrderMatched') {
      setTrades(prev => [event, ...prev].slice(0, 20)); // 保留最新20条
    }
  });

  return (
    <div className="recent-trades">
      <h3>最新成交</h3>
      <ul>
        {trades.map((trade, idx) => (
          <li key={idx}>
            价格: {trade.price.toString()} |
            数量: {trade.size.toString()}
          </li>
        ))}
      </ul>
    </div>
  );
}
```

---

## 📊 合约接口说明

### Pool 合约

#### 只读函数（不需要 gas）

| 函数 | 参数 | 返回值 | 说明 |
|-----|------|--------|------|
| `getOrderbookInfo()` | - | `(lastPrice, askPrice, bidPrice)` | 获取订单簿快照 |
| `getLastPrice()` | - | `uint256` | 获取最新成交价 |
| `fundingIdx()` | - | `uint256` | 获取当前资金费率指数 |
| `maxLeverage()` | - | `uint256` | 获取最大杠杆（600 = 6x） |
| `oraclePrice()` | - | `uint256` | 获取预言机价格 |
| `getPoolInfo()` | - | `(description, lastPrice)` | 获取池子信息 |

#### 写入函数（需要 gas）

| 函数 | 参数 | 说明 |
|-----|------|------|
| `newOrder(margin, order)` | `margin`: 保证金数量<br>`order`: 订单详情 | 创建新订单 |
| `cancelOrder(orderId)` | `orderId`: 订单ID | 取消订单 |
| `closePosition(orderId, order)` | `orderId`: 仓位ID<br>`order`: 平仓订单 | 平仓 |
| `settlePnL(orderId)` | `orderId`: 仓位ID | 结算已关闭的仓位 |

#### 订单类型

```typescript
enum OrderType {
  None = 0,
  Market = 1,   // 市价单：立即按市场最优价成交
  Limit = 2,    // 限价单：指定价格，未成交部分挂单
  FOK = 3,      // 全部成交或取消：必须全部成交否则取消
  IOC = 4,      // 立即成交或取消：立即成交，剩余取消
}

interface PoolOrder {
  isSell: boolean;      // true = 卖出（开空），false = 买入（开多）
  oType: OrderType;     // 订单类型
  size: bigint;         // 合约数量 (18位小数)
  price: bigint;        // 价格 (18位小数)
}
```

### Vault 合约

| 函数 | 参数 | 说明 |
|-----|------|------|
| `balanceOf(address)` | `address`: 用户地址 | 查询用户余额 |
| `deposit(amount)` | `amount`: 充值数量 | 充值到 Vault |
| `withdraw(amount)` | `amount`: 提现数量 | 从 Vault 提现 |

### Position 合约

| 函数 | 参数 | 说明 |
|-----|------|------|
| `getPosition(orderId)` | `orderId`: 仓位ID | 获取仓位详情 |
| `ownerOf(orderId)` | `orderId`: 仓位ID | 获取仓位所有者 |
| `isAuthorized(orderId, user)` | `orderId`: 仓位ID<br>`user`: 用户地址 | 检查授权 |

### IndexOracle 合约

| 函数 | 参数 | 说明 |
|-----|------|------|
| `indexPrice(pool)` | `pool`: 池子地址 | 获取指数价格 |
| `calculateFundingRate(pool)` | `pool`: 池子地址 | 计算资金费率 |
| `getAveragePremiumIndex(pool)` | `pool`: 池子地址 | 获取平均溢价指数 |

---

## 🎨 UI 建议

### 推荐页面结构

1. **交易页面**
   - 订单簿深度图
   - TradingView K线图
   - 交易表单（开多/开空）
   - 最新成交列表
   - 当前持仓卡片

2. **仓位管理页面**
   - 持仓列表（含未实现盈亏、强平价）
   - 挂单列表
   - 历史订单

3. **账户页面**
   - 余额总览
   - 充值/提现
   - 交易历史
   - 手续费统计

### 推荐 UI 库

- **shadcn/ui** - 现代化组件库
- **Recharts** - 图表库
- **TradingView Lightweight Charts** - 专业K线图

---

## 🔐 安全注意事项

1. **验证用户输入**
   - 检查数字格式
   - 防止整数溢出
   - 验证地址格式

2. **错误处理**
   ```typescript
   try {
     await createOrder(params);
   } catch (error) {
     if (error.code === 'ACTION_REJECTED') {
       console.log('用户拒绝签名');
     } else if (error.code === 'INSUFFICIENT_FUNDS') {
       console.log('余额不足');
     } else {
       console.error('交易失败:', error.message);
     }
   }
   ```

3. **交易确认**
   - 等待区块确认后再更新 UI
   - 提供交易状态反馈
   - 显示区块浏览器链接

4. **敏感信息**
   - 永远不要暴露私钥
   - 不要在前端存储助记词
   - 使用环境变量管理配置

---

## 🧪 测试建议

### 本地测试

```bash
# 启动本地测试网
anvil

# 部署合约到本地网络
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

### 前端测试

```typescript
// src/tests/trading.test.ts
import { render, screen, fireEvent } from '@testing-library/react';
import { TradingPanel } from '@/components/TradingPanel';

test('should create market order', async () => {
  render(<TradingPanel />);

  const buyButton = screen.getByText('市价买入');
  fireEvent.click(buyButton);

  // 验证交易发送
  expect(screen.getByText('处理中...')).toBeInTheDocument();
});
```

---

## 📚 参考资源

- [Wagmi 文档](https://wagmi.sh)
- [RainbowKit 文档](https://rainbowkit.com)
- [Ethers.js 文档](https://docs.ethers.org)
- [Viem 文档](https://viem.sh)
- [Foundry 文档](https://book.getfoundry.sh)

---

## ❓ 常见问题

### Q: 如何处理交易失败？

A: 使用 try-catch 捕获错误，并根据错误代码显示友好提示：

```typescript
const { error } = useCreateOrder();

if (error) {
  if (error.message.includes('LeverageOverflow')) {
    alert('杠杆倍数超过限制');
  } else if (error.message.includes('InsufficientBalance')) {
    alert('余额不足');
  }
}
```

### Q: 如何显示正确的小数位数？

A: 使用 `formatUnits` 和 `parseUnits`：

```typescript
import { formatUnits, parseUnits } from 'viem';

// 18位小数 -> 可读字符串
const priceStr = formatUnits(price, 18); // "1000.123456"

// 字符串 -> 18位小数
const priceBigInt = parseUnits("1000.12", 18);
```

### Q: 如何获取交易历史？

A: 查询合约事件：

```typescript
const logs = await poolContract.queryFilter(
  poolContract.filters.OrderMatched(),
  -10000  // 最近10000个区块
);
```

---

## 🤝 贡献指南

如果发现文档问题或想要补充内容，请：

1. Fork 项目
2. 创建分支
3. 提交 Pull Request

---

**祝开发顺利！如有问题请在 GitHub Issues 提出。**
