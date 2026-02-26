# Market Maker Bot — 启动前必读

## 策略说明

网格 + Martingale 做市策略：
- 在 oracle 价格两侧各挂 N 档限价单（buy/sell）
- 某档成交后，自动在对面挂止盈平仓单
- 连续亏损后按 martingale 倍数放大下一档仓位大小

## 配置步骤

```bash
cp .env.example .env
```

**重要**：做市商钱包必须是**独立钱包**，不要用部署者私钥。

填写 `.env`：

| 变量 | 说明 | 来源 |
|------|------|------|
| `RPC_URL` | Sepolia RPC 节点 URL | Alchemy / Infura |
| `PRIVATE_KEY` | 做市商钱包私钥（独立钱包） | 新建一个钱包 |
| `POOL_ADDRESS` | Pool 合约地址 | `deploy.sh` 输出 |
| `VAULT_ADDRESS` | Vault 合约地址 | `deploy.sh` 输出 |
| `TOKEN_ADDRESS` | MockUSDC 合约地址 | `deploy.sh` 输出 |

网格参数（默认值适合测试网演示，按需调整）：

```env
GRID_LEVELS=3       # 每侧挂单档数（买3档 + 卖3档 = 6个挂单）
GRID_STEP=1.0       # 档位间距（单位与 oracle 价格相同，6位小数）
BASE_SIZE=1.0       # 每档基础仓位大小（USDC，6位小数）
BASE_MARGIN=20.0    # 每档基础保证金（USDC）
MAX_LEVERAGE=4      # 最大杠杆（<=10，建议保守设4）
```

## 启动前必做：向 Vault 充值

做市商钱包需要在 Vault 里有余额才能挂单。
最低所需资金 = `BASE_MARGIN × GRID_LEVELS × 2 × MARTINGALE_MULT^MARTINGALE_MAX_LEVEL`
（默认参数：20 × 3 × 2 × 2^4 = 1920 USDC）

```bash
# 1. 先从 MockUSDC faucet 领取测试币
cast send $TOKEN_ADDRESS "mint(address,uint256)" \
  $MAKER_WALLET_ADDRESS 10000000000 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# 2. 授权 Vault 花费 USDC
cast send $TOKEN_ADDRESS "approve(address,uint256)" \
  $VAULT_ADDRESS 10000000000 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# 3. 充值到 Vault
cast send $VAULT_ADDRESS "deposit(uint256)" 5000000000 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

也可以通过前端界面操作充值。

## 启动

```bash
npm install

# 开发模式（直接运行 TypeScript）
npx ts-node src/index.ts

# 生产模式
npm run build
node dist/index.js
```

## 注意事项

- Bot 启动时会检查 Vault 余额，不足时只打 warn，不会退出，但挂单会失败
- Oracle 服务必须先跑起来并推送过至少一次价格，bot 才能获取到 mid price
- 如果 oracle 还没推价格，bot 会用 `lastPrice`（也是0），导致网格以价格0为中心报错
- `POLL_INTERVAL`（ms）控制轮询频率，测试网 5000ms（5秒）即可
