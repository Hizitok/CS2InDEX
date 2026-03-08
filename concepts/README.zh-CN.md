# CS2Index

[English](README.md) | [简体中文](README.zh-CN.md)

**On-Chain Perpetual Futures for Game Item Market Indices**  
**面向游戏饰品价格指数的链上永续合约协议**

CS2Index 是一个面向 CS2（Counter-Strike 2）饰品市场价格指数的完全链上永续合约交易协议。用户可以使用最高 10x 杠杆围绕指数做多或做空，以 USDC 结算，并且无需托管底层游戏资产。协议跟踪的是价格指数本身，并通过基于 Order Statistics Tree 的完全链上订单簿完成撮合。

> **已部署网络：** Unichain Sepolia（测试网）
> **主网上线目标：** Unichain Mainnet（计划于 2026 年 Q2）
> **英文文档：** [README.md](README.md)

---

<a id="overview-cn"></a>
## 项目概览

CS2Index 正在把数十亿美元规模的 CS2 饰品经济升级为一个 24/7 可交易、以 USDC 结算、完全链上可验证的衍生品市场。它解决的是当前饰品经济里的几个核心痛点：Steam 锁仓、单边毁约、场外流动性割裂，以及缺失的对冲工具。

<a id="audience-cn"></a>
## 目标用户

| 用户类型 | 他们的需求 | CS2Index 带来的能力 |
|----------|------------|----------------------|
| 饰品持有者与工作室 | 在锁仓期和高波动行情中对冲库存风险 | 无需处理实物交割，即可获得链上做空能力 |
| 做市商与专业交易者 | 透明执行、确定性定价、可组合仓位 | 完全链上订单簿、逐仓保证金、NFT 仓位 |
| 加密原生用户 | 参与游戏经济 beta，但不想学习复杂的饰品交割流程 | 直接获得以 USDC 结算的指数敞口 |
| 钱包、社区与数据产品 | 可集成、可分析、可分发的新型底层原语 | 指数基础设施、订单簿数据、可转移的仓位 NFT |

<a id="value-cn"></a>
## 核心价值

- **为虚拟商品提供真实对冲能力**：把做空和永续合约引入目前仍以现货风险为主的游戏饰品市场。
- **不托管游戏资产**：协议不接触实物饰品，降低运营与合规摩擦。
- **市场结构可验证**：撮合、资金费、清算、结算全部发生在链上。
- **更高资金效率**：用户以 USDC 保证金交易指数，而不是采购和囤积实物饰品。
- **更强可组合性**：仓位是 ERC-721 NFT，可被转移、集成和二次开发。

## 目录

- [项目概览](#overview-cn)
- [目标用户](#audience-cn)
- [核心价值](#value-cn)
- [1. 为什么是 CS2Index](#why-cn)
- [2. 工作机制](#how-cn)
- [3. 架构](#architecture-cn)
- [4. 合约说明](#contracts-cn)
- [5. 订单簿设计](#orderbook-cn)
- [6. 仓位生命周期](#lifecycle-cn)
- [7. 资金费机制](#funding-cn)
- [8. 保证金与清算](#margin-cn)
- [9. 费率结构](#fees-cn)
- [10. 关键参数](#params-cn)
- [11. 快速开始](#getting-started-cn)
- [12. 部署](#deployment-cn)
- [13. 安全性](#security-cn)

---

<a id="why-cn"></a>
## 1. 为什么是 CS2Index

### 市场问题：一个价值 50-80 亿美元却没有对冲工具的市场

CS2 饰品市场是全球最大的虚拟物品经济之一，估算市值约为 **50-80 亿美元**，活跃玩家超过 **3500 万**。Steam 和第三方平台（Buff163、SkinFlow、EsportFire）上的年交易额超过 **30-50 亿美元**。

但在这样的大市场里，饰品持有者几乎 **没有对冲手段**：

- **没有做空机制**：交易者无法在价格下跌时获利，也无法对冲现货下跌风险
- **没有衍生品市场**：几乎不存在面向饰品资产的期货或期权市场
- **Steam T+7 锁定**：成交后物品会被锁定 7 天，而且任一方都可能取消交易，双方都暴露在不可对冲的价格风险里

**两个典型风险场景：**

```text
你以 500 美元买入一把刀，T+7 锁定开始。
  第 4 天：市场下跌 20%，这把刀现在只值 400 美元。
  第 7 天：锁定结束。你在没有任何对冲工具的情况下承受了 100 美元亏损。
```

```text
你以 500 美元买入一把刀，第 1 天价格暴涨 30%。
  第 3 天：卖家取消交易并收回饰品。
  结果：你并没有在上涨期间真正拥有这件资产，也没有追索手段。
```

### 解决方案：链上指数永续合约

CS2Index 提供的是围绕 CS2 饰品价格指数的 **24/7 可交易、以 USDC 结算的永续合约**。核心特征如下：

| 属性 | 说明 |
|------|------|
| 无需托管 | 协议永远不会持有任何游戏饰品 |
| 现金结算 | 所有盈亏都以 USDC 结算 |
| 无许可访问 | 全球用户可访问，无需 KYC |
| 完全链上 | 订单簿、撮合、结算全部链上可验证 |
| 可组合 | 仓位是 ERC-721 NFT，可转移、可交易 |

**初始支持的指数：**

| 指数 | 覆盖范围 |
|------|----------|
| CS2 Global Index | 全市场（约 50 亿美元市值） |
| CS2 Knives Index | 刀类饰品（约 7 亿美元市值） |
| CS2 Rifles Index | 步枪饰品 |
| CS2 Gloves Index | 手套饰品 |

---

<a id="how-cn"></a>
## 2. 工作机制

```text
用户将 USDC 存入 Vault
          │
          ▼
用户通过 Pool 提交订单（做多/做空，限价/市价）
          │
          ▼
链上 Order Statistics Tree 进行撮合
          │
          ├── 无成交 → 订单留在订单簿中
          │
          └── 成交 → 向用户钱包铸造 Position NFT
                    │
                    ▼
          每 8 小时结算一次资金费（基于 VTWAP）
                    │
                    ▼
          用户主动平仓，或价格触发清算
                    │
                    ▼
          最终以 USDC 结算盈亏并回到 Vault
```

---

<a id="architecture-cn"></a>
## 3. 架构

协议由一个中心 `Factory` 部署的五个核心合约组成：

```text
Factory
  ├── Vault              (USDC 保证金托管)
  ├── Pool               (订单簿 + 撮合引擎)
  ├── PositionNFT        (ERC-721 仓位代币)
  ├── LiquidationEngine  (自动清算引擎)
  └── IndexOracle        (价格预言机 + 资金费)
```

**关键设计决策：**

- **逐仓保证金**：单个仓位的亏损不会影响其他仓位
- **Order Statistics Tree**：`O(log n)` 复杂度的订单簿，无 AMM 滑点
- **VTWAP 预言机**：时间和成交量加权的抗操纵价格
- **全局 `fundingIdx` 累加器**：无论仓位总数多少，每个仓位的资金费结算都能做到 `O(1)`
- **NFT 仓位**：每个成交仓位都是 ERC-721 代币，可转移、可交易

---

<a id="contracts-cn"></a>
## 4. 合约说明

### `Factory.sol`

系统部署器与拥有者，负责：

- 通过 `createPool(name, initialPrice, pxDecimals)` 部署新的交易对（Pool + Engine）
- 持有 Oracle 和 Vault 的所有权（`owner = address(factory)`）
- 维护授权的 Pool 列表
- 设置全局参数（费率、最大杠杆等）
- 通过 `updatePrice(pool, price)` 转发预言机价格更新

### `Vault.sol`

协议内所有 USDC 的唯一托管点，负责：

- 用户 `deposit` 与 `withdraw`
- 内部余额记账（`balances` 映射）
- `internalTransfer(from, to, amount)`：在不触发外部合约调用的前提下移动内部资金，减少可重入攻击面

交易过程中不会发生 ERC-20 的外部转账；所有盈亏都通过 `internalTransfer` 在内部流转。

### `Pool.sol`

核心订单簿与撮合引擎，负责：

- 接收 `newOrder(margin, PoolOrder)`，支持限价单、市价单、做多、做空
- 基于 Order Statistics Tree 运行价格优先、时间优先的撮合循环
- 收取 maker/taker 费并转入协议费账户
- 每次成交后更新 Oracle 中的 VTWAP 累加器
- 通过 PositionNFT 铸造、更新、销毁仓位 NFT
- 将新开仓位注册到 LiquidationEngine

### `PositionNFT.sol`

每个代币都代表一个交易仓位的 ERC-721 合约。

```solidity
struct Position {
    bool     isShort;           // true = 空头, false = 多头
    posStatus status;           // pendingOpen / open / closed / settled
    uint256  openMargin;        // 开仓保证金（USDC，6 位小数）

    uint128  pendingSize;       // 尚未成交的订单数量
    uint128  openSize;          // 已成交仓位数量
    uint128  closeSize;         // 已平仓数量
    uint128  openAmount;        // 累计开仓成交额（price × size）
    uint128  closeAmount;       // 累计平仓成交额
    uint128  openFundingIdx;    // 开仓时记录的 fundingIdx 快照
    uint128  closeFundingIdx;   // 平仓时记录的 fundingIdx 快照
}
```

Position NFT 是标准 ERC-721 代币，可在任何 NFT 市场转移、挂牌或出售。转移 NFT 就等于转移底层仓位所有权。

### `LiquidationEngine.sol`

自动清算监控器，职责包括：

- 维护一个按照清算触发价排序的未平仓位队列（使用 Order Statistics Tree）
- 暴露无许可的 `liquidate()` 方法，任何账户都能执行待清算仓位
- 为每个仓位计算 `triggerPrice` 和 `bankruptcyPrice`
- 以破产价把强平平仓单放入 Pool 订单簿

### `IndexOracle.sol`

负责价格喂价与资金费结算，提供：

- 链上存储的链下指数价格（由 Factory 授权的报价者约每 5 分钟更新一次）
- VTWAP 累加器，由 Pool 在每次成交后更新
- 通过 `calculateFundingRate(pool)` 计算资金费率
- 通过 `applyFundingRate(pool)` 应用资金费率，可每 8 小时调用一次
- 维护全局 `fundingIdx` 累加器
- 价格过期检测（30 分钟不更新则暂停新交易）

---

<a id="orderbook-cn"></a>
## 5. 订单簿设计

### Order Statistics Tree

订单簿通过 **Order Statistics Tree（OST）** 实现。它本质上是一个增强型红黑树，每个节点都存储子树大小，因此支持 `O(log n)` 的排名查询。

| 操作 | 复杂度 |
|------|--------|
| 插入 | `O(log n)` |
| 删除 | `O(log n)` |
| 获取最小/最大价格 | `O(log n)` |
| 统计低于某价格的订单数 | `O(log n)` |

每个 Pool 维护两个独立的 OST：一个用于买单（bid），一个用于卖单（ask）。

### 订单撮合

撮合遵循 **价格优先、时间优先**：

| 订单类型 | 撮合规则 |
|----------|----------|
| 市价买单 | 按从低到高的卖单价格依次吃单，直到完全成交或卖盘耗尽 |
| 市价卖单 | 按从高到低的买单价格依次吃单，直到完全成交或买盘耗尽 |
| 限价买单 | 若最优卖价 ≤ 限价，则立即成交（taker）；否则挂入买单树（maker） |
| 限价卖单 | 若最优买价 ≥ 限价，则立即成交（taker）；否则挂入卖单树（maker） |

支持部分成交。状态为 `pendingOpen` 的仓位会一直留在订单簿中，直到完全成交或被取消。

### 链上订单簿 vs AMM

| 维度 | AMM（如 Uniswap V3） | CS2Index（订单簿） |
|------|----------------------|---------------------|
| 限价单 | 不支持 | 原生支持 |
| 价格滑点 | 随成交量增大 | 对限价单为零滑点 |
| 成交确定性 | 受流动性曲线影响 | 价格结果可预测 |
| 市场深度可见性 | 隐式 | 显式、完全链上 |
| 最适场景 | 高频现货 | 衍生品、专业交易 |

---

<a id="lifecycle-cn"></a>
## 6. 仓位生命周期

### 状态机

```text
pendingOpen  ←─ 订单已提交（未成交）
     │
     │  订单撮合
     ▼
   open  ──────────────────────────────┐
     │                                 │
     │  用户发起平仓                   │  价格触发清算线
     ▼                                 ▼
pendingClose                      liquidating
     │                                 │
     │  平仓单撮合完成                 │  清算单撮合完成
     ▼                                 ▼
  closed ◄────────────────────────────┘
     │
     │  盈亏结算回 Vault，NFT 销毁
     ▼
 settled
```

### 状态说明

| 状态 | 含义 |
|------|------|
| `pendingOpen` | 订单已提交，等待对手方撮合 |
| `open` | 仓位已全部或部分成交，并处于活跃状态 |
| `pendingClose` | 平仓单已提交，等待成交 |
| `liquidating` | 已触发清算线，清算平仓单已挂入订单簿 |
| `closed` | 平仓单已成交，盈亏已计算 |
| `settled` | 盈亏已结算回 Vault，NFT 已销毁 |

如果一个 `pendingClose` 仓位在等待平仓时又触发清算价，系统会优先执行清算，避免用户通过设置一个无法成交的平仓价格来规避强平。

---

<a id="funding-cn"></a>
## 7. 资金费机制

资金费用于把永续合约价格锚定到指数价格。每 8 小时，多头和空头之间会发生一次资金费交换。

### 公式

```text
fundingRate = clamp(premiumIndex + interestRate, −maxFR, +maxFR)
```

| 参数 | 数值 | 说明 |
|------|------|------|
| `premiumIndex` | 动态 | `(VTWAP − oraclePrice) / oraclePrice × 10000`（单位：bp） |
| `interestRate` | 100 bp（1%） | 固定基础利率，用于激励空头侧做市 |
| `maxFR` | 200 bp（2%） | 单个结算周期的资金费上限 |
| `fundingPeriod` | 8 小时 | 结算周期 |

**经济效果：**

- 当 VTWAP > 预言机价格时（多头溢价），多头向空头支付资金费
- 当 VTWAP < 预言机价格时（空头溢价），空头向多头支付资金费
- 固定 `interestRate` 为流动性提供者提供基础激励

### VTWAP 计算

每笔成交对 VTWAP 的贡献权重为：

```text
weight_i = min(Δt_i, 3600) × size_i
```

其中 `Δt_i` 是距离上一笔成交的秒数，`size_i` 是本次成交的 USDC 名义价值。对 `Δt` 设置 1 小时上限，是为了避免长时间无成交后的一笔交易对 VTWAP 产生过强影响。

```text
VTWAP = Σ(price_i × weight_i) / Σ(weight_i)
```

**操纵成本：** 若想通过洗盘交易推动 VTWAP，攻击者每交易 1 美元名义规模需要承担 `(0.3% + 0.5%) × 2 = 1.6%` 的成本。之后真实交易会继续稀释这种操纵影响。

### `fundingIdx` 全局累加器

为了避免对每个仓位逐一做 `O(n)` 结算，协议使用全局累加器：

```text
fundingIdx  +=  fundingRate × oraclePrice    （每 8 小时一次）
```

每个仓位在开仓时记录一个 `openFundingIdx` 快照。平仓时的资金费为：

```text
fundingPayment = openSize × (fundingIdx_close − fundingIdx_open)
```

- 多头仓位：正值表示多头需要支付给空头（从保证金里扣除）
- 空头仓位：正值表示空头从多头获得资金费（计入保证金）

`fundingIdx` 初始值为 `0`，并采用累加方式，避免出现 Q128 精度溢出。

---

<a id="margin-cn"></a>
## 8. 保证金与清算

### 逐仓保证金

每个仓位都采用 **逐仓保证金**：每个仓位的抵押品彼此隔离。一个仓位的亏损不会连带影响其他仓位。单个仓位的最大亏损也不会超过该仓位存入的保证金。

### 触发价（清算阈值）

**多头仓位触发价：**

```text
triggerPrice_long = entryPrice × (1 − (1 − maintenanceMarginRatio) / leverage)
```

**空头仓位触发价：**

```text
triggerPrice_short = entryPrice × (1 + (1 − maintenanceMarginRatio) / leverage)
```

其中 `maintenanceMarginRatio = 20%`。

**示例（5x 杠杆多头，开仓价 100 美元）：**

```text
triggerPrice = 100 × (1 − (1 − 0.20) / 5) = 100 × 0.84 = $84
```

触发价会受到累计资金费影响。当资金费持续对仓位不利时，实际清算触发价会不断向当前市价靠近，即使价格本身不动，也可能最终触发清算。

### 破产价

保证金恰好归零时的价格：

```text
bankruptcyPrice_long  = entryPrice × (1 − 1/leverage)
bankruptcyPrice_short = entryPrice × (1 + 1/leverage)
```

### 两段式清算

**第 1 步：触发扫描（无许可）**

任何人都可以调用 `LiquidationEngine.liquidate()`。引擎会遍历已排序的仓位队列，找出预言机价格已经穿越 `triggerPrice` 的仓位。

**第 2 步：把清算单放入订单簿**

对每个被触发的仓位：

1. 仓位状态被设置为 `liquidating`
2. 在 Pool 中以 `bankruptcyPrice` 放置平仓限价单
3. 从剩余保证金中扣除清算奖励
4. 更新 PositionNFT 状态

**第 3 步：按正常撮合流程成交**

清算平仓单会进入标准订单簿。成交后：

1. 计算包含资金费和手续费在内的盈亏
2. 将净收益结算回原持仓人的 Vault 余额
3. NFT 被销毁，仓位进入 `settled`

---

<a id="fees-cn"></a>
## 9. 费率结构

| 费率类型 | 费率 | 说明 |
|----------|------|------|
| Maker fee | 0.3% | 由挂单进入订单簿的一方支付 |
| Taker fee | 0.5% | 由主动触发成交的一方支付 |
| Funding rate | 每 8 小时上限 ±2% | 在多头和空头之间流转，不归协议所有 |

手续费以 USDC 计价，并通过 `Vault.internalTransfer` 从成交额中扣除。Maker 与 Taker 的 0.2% 费差用于激励流动性提供者，并抑制过度使用市价单。

---

<a id="params-cn"></a>
## 10. 关键参数

| 参数 | 数值 | 说明 |
|------|------|------|
| `MAKERFEE` | `3000` → 0.3% | `amount × 3000 / 1e6` |
| `TAKERFEE` | `5000` → 0.5% | `amount × 5000 / 1e6` |
| `maxLeverage` | `1000` → 10x | 存储形式为 `leverage × 100` |
| 维持保证金率 | 20% | 当保证金低于仓位价值的 20% 时触发清算 |
| `fundingPeriod` | 28 800 秒（8 小时） | 结算周期 |
| `maxFundingRate` | 200 bp（2%） | 单个周期的资金费上限 |
| `interestRate` | 100 bp（1%） | 加到 `premiumIndex` 上的固定基础利率 |
| `pxDecimals` | 6 | 与 USDC 对齐的价格精度 |
| 预言机过期阈值 | 1 800 秒（30 分钟） | 价格过期时拒绝新订单 |
| VTWAP 时间上限 | 3 600 秒（1 小时） | 每笔成交权重里使用 `min(Δt, 3600)` |

---

<a id="getting-started-cn"></a>
## 11. 快速开始

### 前置要求

- [Foundry](https://book.getfoundry.sh/getting-started/installation)（`forge`、`cast`、`anvil`）

### 安装

```bash
git clone https://github.com/izit1/CS2Index.git
cd CS2Index
forge install
```

### 构建

```bash
forge build
```

### 运行测试

```bash
# 运行全部测试
forge test

# 查看更详细的日志
forge test -vv

# 运行指定测试
forge test --match-test testFullTradingFlow -vv

# 输出完整 trace（调试模式）
forge test --match-test testLiquidationEngine -vvvv

# Gas 基准测试
forge test --match-test testGasBenchmark_1000Orders -vv
```

### 测试覆盖率

```bash
forge coverage
```

测试套件包括：

| 测试文件 | 覆盖内容 |
|----------|----------|
| `Integration.t.sol` | 完整交易流程、预言机更新、订单簿深度、Vault 操作、撤单、部分成交、资金费结算、清算引擎、交叉盘口撮合、清算诊断 |
| `GasBenchmark.t.sol` | 2000 笔订单压力测试与 gas 分布报告 |
| `InternalGasTest.t.sol` | 编译器优化分析 |

---

<a id="deployment-cn"></a>
## 12. 部署

### 配置

Pool 参数定义在 [deploy/pools.config.json](deploy/pools.config.json)：

```json
[
  { "name": "CS2 Global Index",  "initialPrice": 393500000, "pxDecimals": 6 },
  { "name": "CS2-Knives-Index",  "initialPrice":  80000000, "pxDecimals": 6 },
  { "name": "CS2-Rifles-Index",  "initialPrice":  30000000, "pxDecimals": 6 },
  { "name": "CS2-Gloves-Index",  "initialPrice":  40000000, "pxDecimals": 6 }
]
```

> 原始价格 = 实际价格 × 10^pxDecimals，例如 `$393.50` 对应 `393500000`

如果要新增或调整 Pool，只需编辑这个 JSON 文件，无需修改 Solidity 代码。

### 环境变量

复制示例文件并填写参数：

```bash
cp deploy/.env.example deploy/.env
```

```bash
PRIVATE_KEY=0x...           # 部署者私钥
USDC_ADDRESS=0x...          # 测试网可留空（会自动部署 MockUSDC）
DEPLOYER_MINT=1000000000000 # 测试网为部署者增发的 USDC 数量（可选）
```

### 部署到测试网

```bash
forge script deploy/Deploy.s.sol \
  --rpc-url <YOUR_RPC_URL> \
  --broadcast \
  --verify \
  -vvvv
```

### 部署到主网

```bash
USDC_ADDRESS=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 \
forge script deploy/Deploy.s.sol \
  --rpc-url <MAINNET_RPC_URL> \
  --broadcast \
  --verify \
  --slow \
  -vvvv
```

部署地址会写入 `deploy/deployed.<chainId>.json`。

### 部署输出示例

```text
[MockUSDC]  deployed: 0x...
[Factory]   deployed: 0x...
[Vault]     deployed: 0x...
[Oracle]    deployed: 0x...
[NFT]       deployed: 0x...
[Pool]      CS2 Global Index
            pool  : 0x...
            engine: 0x...
[Router]    deployed: 0x...
```

---

<a id="security-cn"></a>
## 13. 安全性

### 访问控制

| 合约 | Owner | 授权调用者 |
|------|-------|------------|
| Oracle | Factory | Factory（价格更新、资金费结算） |
| Vault | Factory | 被 Factory 授权的 Pool 和 Router |
| Pool | Factory | 任意用户（公开下单函数） |
| PositionNFT | Pool | Pool（铸造/更新/销毁）；NFT 持有人（转移） |
| LiquidationEngine | Factory | 任意人（`liquidate()` 无许可） |

### 可重入风险

`Vault.internalTransfer` 只修改内存中的 `balances` 映射，不进行任何外部调用，从而消除了资金流转过程中的可重入攻击面。公开的 `withdraw` 路径遵循 Checks-Effects-Interactions 模式。

### 预言机操纵

- VTWAP 使用 `min(Δt, 3600) × size` 加权，洗盘操纵成本约为 **每 1 美元名义规模 1.6%**
- 链下使用多源聚合（SkinFlow + EsportFire + Buff163）并做中位数过滤
- 若 30 分钟没有价格更新，则暂停新订单
- VTWAP 与预言机价格是两套独立信号，可相互校验

### 已知限制

| 风险 | 状态 |
|------|------|
| 缺少坏账保险基金 | 计划于 2026 年 Q2 增加 |
| 仅有单一预言机上报密钥 | 计划于 2026 年 Q3 升级为多上报者网络 |
| 暂无升级机制（非代理） | 正在评估 UUPS Proxy |
| 清算循环可能受 gas 限制 | 计划增加 `maxIterations` 参数 |

### 审计状态

内部审计已完成，发现并修复了 6 个 critical/high 级别问题（2026 年 Q1）。外部审计已排期。

---

## 许可

[MIT](LICENSE)

---

## 贡献

欢迎提交 Issue 和 Pull Request。若是较大改动，建议先发起讨论。

合约代码位于 [src/](src/)，测试位于 [test/](test/)，部署脚本位于 [deploy/](deploy/)。

---

## 支持

如果你觉得这个项目有价值，欢迎支持后续开发：

| 网络 | 地址 |
|------|------|
| BTC | `bc1pjd7gc79yw7fqek9w6fwlkw28ad52vu8v90s4vy9d52g5pja2nn5sp56kqn` |
| ETH / ERC-20 | `0xd799eba64aaf9cfd2169afc9685494a61d23012d` |
