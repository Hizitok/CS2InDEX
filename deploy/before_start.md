# 合约部署 — 启动前必读

## 部署流程概览

```
deploy.sh sepolia
  ├── forge test（可跳过）
  ├── 部署 MockUSDC（测试网自动部署，主网需填 USDC_ADDRESS）
  ├── 部署 CS2InDEXFactory
  │     └── Factory 构造函数自动部署：
  │           Vault / IndexOracle / PositionNFT / LiquidationEngine
  ├── 调用 Factory.createPool(name, initialPrice, pxDecimals)
  ├── 调用 Factory.setRouter(routerAddress)（如有 Router）
  └── 调用 Factory.updatePrice(pool, initialPrice)（初始化 oracle 价格）
```

## 配置步骤

```bash
cp .env.example .env
```

填写 `.env`：

```env
PRIVATE_KEY=0x你的部署者私钥
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
ETHERSCAN_API_KEY=你的EtherscanKey   # 可选，用于合约验证
```

测试网部署时 `USDC_ADDRESS` **留空**，脚本自动部署 MockUSDC 并向部署者 mint 100万 USDC。

## 执行部署

```bash
bash deploy/deploy.sh sepolia
```

## 部署后记录以下地址

脚本执行完成后会打印所有地址，**复制保存**：

```
Factory:   0x...   → oracle-service FACTORY_ADDRESS
Oracle:    0x...   → oracle-service ORACLE_ADDRESS
Vault:     0x...   → marketmaker VAULT_ADDRESS
MockUSDC:  0x...   → marketmaker TOKEN_ADDRESS
Pool[0]:   0x...   → oracle-service POOL_CONFIGS[0].pool
                   → marketmaker POOL_ADDRESS
```

## 部署后的初始化顺序

1. **先启动 Oracle Service** — 推送初始价格到链上
2. **再启动 Market Maker** — bot 依赖 oracle 价格确定挂单区间
3. **最后开放前端** — 更新 `frontend/src/config/contracts.ts` 里的合约地址

## 验证合约（可选）

```bash
# 单独验证某个合约
forge verify-contract $FACTORY_ADDRESS \
  src/Factory.sol:CS2InDEXFactory \
  --chain sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY
```
