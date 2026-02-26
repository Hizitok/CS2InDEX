# Oracle Service — 启动前必读

## 架构说明

本服务通过 `Factory.updatePrice(poolAddress, price)` 更新链上价格。
调用链：Oracle Service → Factory → IndexOracle → Pool

**关键约束**：`Factory.updatePrice` 是 `onlyOwner`，
所以 `PRIVATE_KEY` **必须是 Factory 的 owner（即部署时的钱包）**。

## 配置步骤

```bash
cp .env.example .env
```

填写 `.env`：

| 变量 | 说明 | 来源 |
|------|------|------|
| `RPC_URL` | Sepolia RPC 节点 URL | Alchemy / Infura |
| `PRIVATE_KEY` | 部署者私钥（Factory owner） | 部署时的钱包 |
| `FACTORY_ADDRESS` | Factory 合约地址 | `deploy.sh` 输出 |
| `ORACLE_ADDRESS` | IndexOracle 合约地址 | `deploy.sh` 输出，或 `cast call $FACTORY "oracle()(address)"` |
| `POOL_CONFIGS` | Pool 地址 + 数据源 JSON 数组 | 见下方示例 |

`POOL_CONFIGS` 示例（每个 Pool 一个条目）：

```env
POOL_CONFIGS='[
  {
    "name": "CS2 Global Index",
    "pool": "0xPOOL_ADDRESS",
    "source": "global-index"
  }
]'
```

可用 `source` 值：`global-index` / `knives-index` / `rifles-index` / `gloves-index`

> 真实 API（SkinFlow / EsportFire）若无法访问，自动 fallback 到 mock 价格（±2% 随机波动），测试网够用。

## 启动

```bash
npm install

# 开发模式（自动重载）
npm run dev

# 生产模式
npm run build
npm start

# 推荐：用 PM2 守护
npm install -g pm2
pm2 start dist/index.js --name cs2index-oracle
pm2 save
```

## 常见问题

**报错 `Not Factory owner`**：PRIVATE_KEY 钱包地址与部署时不一致，检查是否用了正确的私钥。

**价格一直被跳过（`Price change below threshold`）**：价格变动 < 0.1% 时跳过，正常现象（mock 价格随机波动可能较小）。

**tx revert**：检查钱包 ETH 余额是否足够 gas（Sepolia 测试 ETH 可从 faucet 领取）。
