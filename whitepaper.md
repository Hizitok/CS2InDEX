---
Title: CS2InDEX — Technical Whitepaper
Subtitle: On-Chain Perpetual Futures for CS2 Item Market Indices
---

# CS2InDEX 技术白皮书

**On-Chain Perpetual Futures for CS2 Item Market Indices**

---

## 摘要 (Abstract)

CS2InDEX 是一个完全链上的永续合约交易所，允许交易者对 CS2 游戏道具市场指数进行杠杆做多/做空操作。系统以 USDC 作为抵押品，以链上 Order Statistics Tree（增强红黑树）作为撮合引擎，以 ERC721 NFT 作为仓位凭证，以交易间 VTWAP 预言机进行资金费率结算。CS2InDEX 无需托管任何游戏内资产，即可将金融衍生品引入市值超 500 亿美元的 CS2 皮肤市场。

---

## 1. 背景与动机

### 1.1 CS2 皮肤市场概述

CS2（Counter-Strike 2）拥有超过 3500 万活跃玩家，其游戏内皮肤（skin）市场是全球规模最大的虚拟道具市场之一，估计总市值超过 **500 亿美元**。Steam 平台官方市场每日交易量达数百万美元，第三方平台（如 Buff163、SkinFlow.gg、EsportFire.com）的交易量更是数倍于此。

皮肤价格受多重因素驱动：职业赛事热度、皮肤稀缺性（Float 值、贴纸、纹理）、Steam 季节性促销以及玩家社区情绪。价格波动率高，短期内单件皮肤涨跌幅可超过 50%。

### 1.2 问题：缺乏对冲工具

尽管市场规模巨大，皮肤持有者目前缺乏有效的对冲手段：

- **没有做空机制**：持有大量皮肤库存的商人无法锁定风险
- **无期货市场**：皮肤价格单边暴跌时，玩家只能被动承受损失
- **场外合约风险高**：中心化平台的 OTC 衍生品存在交易对手风险

### 1.3 为何选择链上方案

| 特性 | 中心化方案 | CS2InDEX（链上） |
|------|-----------|-----------------|
| 资产托管 | 需托管游戏资产 | 无需托管，USDC 结算 |
| 交易时间 | 受限于平台运营 | 24/7 全天候 |
| 访问门槛 | KYC / 地域限制 | 全球无许可访问 |
| 透明度 | 订单簿不公开 | 完全链上透明 |
| 可组合性 | 孤立生态 | 与 DeFi 协议可组合 |

### 1.4 为何选择永续合约

相较于期权和现货 DEX，永续合约（Perpetual Futures）具有以下优势：

- **无到期日**：无需管理交割日期，持仓可无限期延续
- **现金结算**：以 USDC 结算，无需交割实物皮肤
- **双向交易**：支持做多和做空，提供完整的价格风险管理工具
- **杠杆效率**：相同资金量可获得更大市场敞口

---

## 2. 系统架构

CS2InDEX 由 6 个核心合约组成，形成模块化架构：

```
Factory
  ├── Vault          (USDC 抵押品托管)
  ├── Pool           (订单簿 + 撮合引擎)
  ├── PositionNFT    (ERC721 仓位凭证)
  ├── LiquidationEngine  (清算管理)
  └── IndexOracle    (价格预言机 + 资金费率)
```

### 2.1 Factory.sol — 部署与管理

Factory 是整个系统的管理者，负责：

- 部署新的交易对 Pool 及其配套合约
- 持有 Oracle 和 Vault 的所有权（`owner = address(factory)`）
- 管理授权 Pool 列表
- 设置全局参数（手续费率、杠杆上限等）

Factory 通过 `createPool(assetId, params)` 一键部署完整的交易对生态。

### 2.2 Vault.sol — USDC 抵押品托管

Vault 负责所有资金的安全托管与内部记账：

- 持有用户存入的 USDC 抵押品
- 维护每个用户的内部余额（`balances` mapping）
- 执行内部转账（`internalTransfer`），不触发外部合约调用
- 处理存款（`deposit`）和取款（`withdraw`）
- 记录协议手续费收入

Vault 是资金流动的唯一入口和出口，所有 PnL 结算均通过 `internalTransfer` 完成。

### 2.3 Pool.sol — 订单簿与撮合引擎

Pool 是系统的核心，负责：

- 维护链上订单簿（基于 Order Statistics Tree）
- 接受用户的限价单（`placeLimitOrder`）和市价单（`placeMarketOrder`）
- 执行价格优先、时间优先的撮合逻辑
- 计算并收取 Maker/Taker 手续费
- 更新 VTWAP 累加器
- 调用 Oracle 更新池信息
- 触发 PositionNFT 创建/更新/销毁仓位

Pool 持有对 Vault、Oracle、PositionNFT 和 LiquidationEngine 的引用。

### 2.4 PositionNFT.sol — ERC721 仓位凭证

每个已成交仓位由一枚 ERC721 NFT 表示：

- NFT tokenId 唯一标识一个仓位
- 仓位数据（方向、开仓价、数量、保证金、fundingIdx 快照）存储在合约中
- NFT 可在二级市场交易，实现仓位转让
- NFT 销毁（`burn`）即代表仓位平仓

仓位数据结构：

```solidity
struct Position {
    address owner;
    bool isLong;
    uint256 openPrice;    // 开仓价格（6 位小数）
    uint256 fillSize;     // 仓位大小（以 USDC 计价）
    uint256 margin;       // 保证金（USDC）
    uint256 fundingIdx;   // 开仓时的 fundingIdx 快照
    PositionState state;  // 仓位状态
}
```

### 2.5 LiquidationEngine.sol — 清算管理

LiquidationEngine 负责：

- 维护所有开放仓位的价格触发清单（基于 OS Tree 按清算价格排序）
- 接受任何人调用的 `liquidate(poolId)` 触发批量清算
- 计算每个仓位的清算触发价格（`triggerPrice`）和破产价格（`bankruptcyPrice`）
- 在订单簿中以破产价格放置平仓限价单

### 2.6 IndexOracle.sol — 价格预言机与资金费率

IndexOracle 提供：

- 外部价格数据的链上存储（由授权 reporter 更新）
- VTWAP 累加器的管理（由 Pool 更新）
- 资金费率的计算与结算
- `fundingIdx` 全局累加器的维护
- 价格过期检测（超过 30 分钟未更新则暂停交易）

---

## 3. 订单簿设计

### 3.1 Order Statistics Tree（增强红黑树）

CS2InDEX 使用链上 **Order Statistics Tree（OST）** 作为订单簿的底层数据结构。OST 是在标准红黑树基础上增强的自平衡二叉搜索树，每个节点额外维护子树大小（`size`）。

**核心操作复杂度：**

| 操作 | 复杂度 |
|------|--------|
| 插入（insert） | O(log n) |
| 删除（delete） | O(log n) |
| 查询最小值（getMin） | O(log n) |
| 查询最大值（getMax） | O(log n) |
| 排名查询（rank） | O(log n) |
| 按排名选择（select） | O(log n) |

**支持的查询接口：**

```solidity
function getMin(bytes32 treeKey) external view returns (uint256 minPrice);
function getMax(bytes32 treeKey) external view returns (uint256 maxPrice);
function rank(bytes32 treeKey, uint256 value) external view returns (uint256 rank);
function select(bytes32 treeKey, uint256 rank) external view returns (uint256 value);
```

买单树（bids）和卖单树（asks）各为独立的 OST 实例，以价格为键值排序。

### 3.2 链上订单簿 vs AMM 对比

| 维度 | AMM（如 Uniswap V3） | CS2InDEX（订单簿） |
|------|---------------------|-------------------|
| 限价单 | 不支持 | 原生支持 |
| 滑点 | 随规模增大 | 限价单零滑点 |
| 执行确定性 | 依赖流动性分布 | 价格优先确定执行 |
| 市场深度 | 隐式（流动性分布） | 显式（链上可查） |
| 适合场景 | 高频小额现货 | 衍生品、专业交易 |

对于永续合约场景，订单簿模型更适合：专业做市商可以精确控制挂单价格，套利者可以通过限价单零成本提供流动性，大额交易不因 AMM 曲线产生不必要滑点。

### 3.3 撮合逻辑

撮合采用 **价格优先、时间优先（Price-Time Priority）** 原则：

1. 市价买单：与 asks 树中价格最低的挂单成交
2. 市价卖单：与 bids 树中价格最高的挂单成交
3. 限价买单：若当前最低 ask ≤ 限价，立即成交；否则挂入 bids 树
4. 限价卖单：若当前最高 bid ≥ 限价，立即成交；否则挂入 asks 树

每次成交后，Pool 更新 VTWAP 累加器并通知 Oracle。

---

## 4. 仓位生命周期

### 4.1 状态机

```
pendingOpen
    │
    │ (订单被撮合成交)
    ▼
  open ──────────────────────────────┐
    │                                │
    │ (用户发起平仓)    (价格触发清算) │
    ▼                                ▼
pendingClose              liquidating
    │                                │
    │ (平仓订单成交)    (平仓订单成交) │
    ▼                                ▼
  closed ◄─────────────────────────┘
    │
    │ (PnL 结算至 Vault)
    ▼
 settled
```

### 4.2 各状态说明

| 状态 | 描述 | 触发条件 |
|------|------|---------|
| `pendingOpen` | 开仓订单已提交，等待撮合 | 用户调用 `placeOrder` |
| `open` | 仓位已开仓，持有中 | 开仓订单完全成交 |
| `pendingClose` | 平仓订单已提交，等待撮合 | 用户调用 `closePosition` |
| `liquidating` | 触发清算，平仓单已入订单簿 | 价格穿越 `triggerPrice` |
| `closed` | 仓位已平仓，待结算 | 平仓订单完全成交 |
| `settled` | PnL 已结算至 Vault，NFT 已销毁 | `settle` 函数调用 |

### 4.3 强制平仓规则

处于 `pendingClose` 状态的仓位若同时触发清算条件，系统优先执行清算逻辑，以防止用户通过挂出不可能成交的平仓价格来规避清算。

---

## 5. 资金费率机制

### 5.1 资金费率公式

```
fundingRate = clamp(premiumIndex + interestRate, -maxFR, +maxFR)
```

各参数定义：

| 参数 | 值 | 说明 |
|------|----|------|
| `premiumIndex` | 动态计算 | (VTWAP - oraclePrice) / oraclePrice × BASIS_POINT |
| `interestRate` | 100 bp/周期 (1%) | 固定基础利率 |
| `maxFR` | 200 bp (2%) | 单周期资金费率上限 |
| `fundingPeriod` | 8 小时 | 结算周期 |
| `BASIS_POINT` | 10000 | 基点转换因子 |

**经济含义：**
- 当 VTWAP > 预言机价格（多头溢价），多头向空头支付资金费
- 当 VTWAP < 预言机价格（空头溢价），空头向多头支付资金费
- `interestRate` 提供基础的空头补偿，激励做市商提供流动性

### 5.2 交易间加权 VTWAP 计算

每次成交对 VTWAP 的贡献权重为：

```
weight_i = min(Δt_i, 3600) × size_i
```

其中：
- `Δt_i` = 本次成交距上次成交的秒数
- `size_i` = 本次成交量（以 USDC 计价）
- `3600` = 1 小时上限（秒），防止孤立大单主导 VTWAP

**完整公式：**

```
VTWAP = Σ(price_i × weight_i) / Σ(weight_i)
      = Σ(price_i × min(Δt_i, 3600) × size_i) / Σ(min(Δt_i, 3600) × size_i)
```

**设计动机：**
时间加权的引入使得操纵成本大幅提高。攻击者若试图通过单笔大额成交拉高/压低 VTWAP，其影响将随后续合法交易的时间推移而被稀释。单小时时间上限确保了长时间无成交后的首笔交易也不会无限制放大权重。

### 5.3 fundingIdx 累加器

为避免逐仓位结算的 O(n) 成本，系统使用全局累加器：

**累加规则（每 8 小时）：**

```
fundingIdx += fundingRate × oraclePrice
```

**仓位资金费用计算：**

```
fundingPayment = fillSize × (fundingIdx_close - fundingIdx_open)
```

- `fundingIdx_open`：开仓时记录的全局 `fundingIdx` 快照
- `fundingIdx_close`：平仓/结算时的全局 `fundingIdx`
- 多头仓位：`fundingPayment > 0` 表示支付资金费（从保证金扣除）
- 空头仓位：`fundingPayment > 0` 表示收取资金费（加入保证金）

**初始化：** `fundingIdx` 初始化为 0，使用加法累加（非乘法），避免 Q128 精度溢出问题。

---

## 6. 保证金与清算

### 6.1 隔离保证金（Isolated Margin）

CS2InDEX 采用隔离保证金模式：

- 每个仓位的保证金完全独立，互不影响
- 单个仓位亏损不会蔓延到同一账户的其他仓位
- 最大损失限于该仓位投入的保证金
- 用户可为每个仓位单独设置风险偏好

### 6.2 清算触发价格

**多头仓位清算触发价格：**

```
triggerPrice_long = openPrice × (1 - (1 - maintenanceMarginRatio) / leverage)
```

**空头仓位清算触发价格：**

```
triggerPrice_short = openPrice × (1 + (1 - maintenanceMarginRatio) / leverage)
```

参数：
- `maintenanceMarginRatio` = 20%（维持保证金率）
- `leverage` = 用户选择的杠杆倍数（最大 6x）
- `openPrice` = 仓位开仓成交均价

**示例（6x 杠杆多头，开仓价 100 USDC）：**

```
triggerPrice = 100 × (1 - (1 - 0.20) / 6) = 100 × (1 - 0.1333) = 86.67 USDC
```

### 6.3 破产价格（Bankruptcy Price）

破产价格是保证金归零时对应的标记价格：

**多头破产价格：**

```
bankruptcyPrice_long = openPrice × (1 - 1 / leverage)
```

**空头破产价格：**

```
bankruptcyPrice_short = openPrice × (1 + 1 / leverage)
```

清算订单以破产价格作为限价挂入订单簿，确保系统不承担超额亏损。若市场深度不足导致成交价格更差，超额亏损由协议保险基金（Insurance Fund）承担。

### 6.4 两步清算流程

**第一步：触发扫描**

任何人均可调用 `liquidationEngine.liquidate(poolId)` 触发批量清算扫描：

```
1. 从 OS Tree 中按触发价格顺序遍历仓位
2. 对每个满足 currentPrice ≤ triggerPrice（多头）或
   currentPrice ≥ triggerPrice（空头）的仓位执行清算
3. 限制单次调用的最大迭代次数（maxIterations），避免 gas 超限
```

**第二步：订单簿平仓**

对每个触发的仓位：

```
1. 将仓位状态更新为 liquidating
2. 在 Pool 的订单簿中以 bankruptcyPrice 放置平仓限价单
3. 扣除清算人奖励（liquidation bonus）
4. 通知 PositionNFT 更新状态
```

**第三步：正常撮合结算**

清算平仓单进入普通撮合流程：

```
1. 与对手方订单成交
2. PnL 计算：realizedPnL = (closePrice - openPrice) × fillSize / openPrice
3. 减去资金费用和手续费
4. 净值通过 Vault.internalTransfer 结算
5. PositionNFT 销毁（burn），仓位进入 settled 状态
```

---

## 7. 预言机设计

### 7.1 链下价格聚合

**数据来源：**

| 平台 | 地区 | 货币 | 权重 |
|------|------|------|------|
| SkinFlow.gg | 全球 | USD | 1/3 |
| EsportFire.com | 欧洲 | EUR→USD | 1/3 |
| Buff163 | 中国 | CNY→USD | 1/3 |

**聚合方法：**

```
1. 从各数据源拉取最新 N 件皮肤的成交价格
2. 各平台内部计算加权中位数（按流动性权重）
3. 汇率转换至 USD（使用 Chainlink 汇率预言机）
4. 对 N 个来源取中位数，过滤异常值（Chauvenet 准则）
5. 将结果以 6 位小数精度推送至链上
```

**更新频率：** 每 5 分钟推送一次

**过期阈值：** 超过 30 分钟未更新，合约自动暂停开仓操作（现有仓位仍可平仓和清算）

### 7.2 链上 VTWAP 作为抗操纵层

链上 VTWAP 提供了第二个独立的价格信号：

- **资金费率使用 VTWAP 而非原始预言机价格**，短期预言机异常不直接影响资金费率
- VTWAP 基于实际链上成交，无法被链下数据源攻击
- 两个价格信号互为校验，系统整体操纵成本大幅提高

### 7.3 价格精度

所有价格以 6 位小数精度（`pxDecimals = 6`）存储，与 USDC 精度一致：

```
价格 1.234567 USDC → 存储为 1234567 (uint256)
```

---

## 8. 手续费结构

### 8.1 费率设置

| 类型 | 费率 | 说明 |
|------|------|------|
| Maker Fee | 0.3% (`MAKERFEE = 3000 / 1e6`) | 挂单方（提供流动性） |
| Taker Fee | 0.5% (`TAKERFEE = 5000 / 1e6`) | 吃单方（消耗流动性） |

### 8.2 费率计算

```
makerFeeAmount = fillSize × MAKERFEE / 1e6
takerFeeAmount = fillSize × TAKERFEE / 1e6
```

所有手续费以 USDC 计价，直接从成交金额中扣除，通过 `Vault.internalTransfer` 转入协议手续费账户。

### 8.3 费率激励分析

Maker-Taker 费率差异（Taker 比 Maker 多付 0.2%）形成激励：

- 专业做市商通过挂限价单赚取相对较低的 Maker Fee，同时为市场提供深度
- 套利机器人承担 Taker Fee 的同时，纠正价格偏差，维持市场效率
- 协议净收入 = Taker Fee - （Maker Fee 作为做市商激励）

---

## 9. 安全性分析

### 9.1 访问控制

系统采用分层权限模型：

| 合约 | Owner | 授权调用者 |
|------|-------|-----------|
| Oracle | Factory | Factory 授权的 Pool |
| Vault | Factory | Factory 授权的 Pool |
| Pool | Factory | 任何用户（公开函数） |
| PositionNFT | Pool | Pool（铸造/销毁），NFT 持有者（转让） |
| LiquidationEngine | Factory | 任何人（liquidate 函数） |

所有状态修改路径均有 `require(msg.sender == authorizedCaller)` 守卫。

### 9.2 重入攻击防护

Vault 遵循 **Checks-Effects-Interactions（CEI）** 模式：

```solidity
function withdraw(uint256 amount) external {
    // Checks
    require(balances[msg.sender] >= amount, "Insufficient balance");
    // Effects
    balances[msg.sender] -= amount;
    // Interactions
    IERC20(usdc).transfer(msg.sender, amount);
}
```

`internalTransfer` 函数仅修改内部 `balances` mapping，不调用任何外部合约，从根本上消除重入风险。

### 9.3 预言机操纵防护

**自成交攻击（Wash Trading）成本分析：**

攻击者若试图通过自成交操纵 VTWAP：

```
单次往返成本 = (Maker Fee + Taker Fee) × 2 = (0.3% + 0.5%) × 2 = 1.6%
```

即攻击者每操纵 1 美元名义价值的 VTWAP，需支付 1.6 美分。

**时间加权稀释效应：**

VTWAP 权重 `min(Δt, 3600) × size` 意味着：

1. 攻击者的大额单次成交权重受 `min(Δt, 3600)` 限制
2. 后续的合法交易会随时间推移逐步稀释攻击影响
3. 要持续操纵 VTWAP，攻击者必须连续支付高额费用

**预言机失效保护：**

- 价格 30 分钟未更新 → 自动暂停开仓
- 多数据源聚合 → 单一来源异常不影响整体
- VTWAP 双重验证 → 链下预言机异常不直接触发资金费率异常

### 9.4 已知风险与改进计划

| 风险 | 当前状态 | 改进计划 |
|------|---------|---------|
| 清算循环 Gas 超限 | 无 maxIterations 限制 | 增加 maxIterations 参数（Q1 2026） |
| 单一预言机来源 | 单一 reporter | 多数据源聚合（Q3 2026） |
| 预言机中心化 | 单一 reporter 密钥 | 去中心化 reporter 网络（Q3 2026） |
| 保险基金缺失 | 未实现 | 手续费一部分注入保险基金（Q2 2026） |
| 无法升级 | 非代理模式 | 评估 UUPS 代理模式（Q2 2026） |

---

## 10. 技术路线图

### Q1 2026 — 测试网与外部审计

- [ ] 部署至 Arbitrum Sepolia 测试网
- [ ] 完成单元测试覆盖率 > 95%
- [ ] 委托两家独立安全公司进行智能合约审计
- [ ] 修复审计发现的所有 Critical 和 High 级别漏洞
- [ ] 公开 Bug Bounty 计划启动

### Q2 2026 — Arbitrum 主网上线与代币发行

- [ ] 主网部署（Arbitrum One）
- [ ] 初始流动性挖矿计划
- [ ] 协议治理代币（INDEX）TGE
- [ ] 基础保险基金建立（初始注入 50 万 USDC）
- [ ] 第一批皮肤指数上线（AK-47 指数、刀具指数）

### Q3 2026 — 多源预言机与去中心化

- [ ] 多数据源预言机聚合（SkinFlow + EsportFire + Buff163 + CSFloat）
- [ ] 去中心化 reporter 网络（基于 Stake-weighted 共识）
- [ ] 新增皮肤指数（手套、步枪、手枪）
- [ ] 跨保证金模式支持（可选）
- [ ] 移动端 DApp 上线

### Q4 2026 — 生态基础设施与 DAO 治理

- [ ] The Graph 索引器部署（历史交易数据查询）
- [ ] 开放 REST/WebSocket API（面向量化交易机器人）
- [ ] DAO 治理上线（参数修改、新指数上线均需投票）
- [ ] 跨链部署评估（Optimism、Base）
- [ ] SDK 发布（JavaScript / Python）

---

## 附录 A：合约参数参考

| 参数 | 值 | 说明 |
|------|----|------|
| `MAKERFEE` | `3000` (3000/1e6 = 0.3%) | Maker 手续费率 |
| `TAKERFEE` | `5000` (5000/1e6 = 0.5%) | Taker 手续费率 |
| `maxLeverage` | `600` (600/100 = 6x) | 最大杠杆倍数 |
| `maintenanceMarginRatio` | `20%` | 维持保证金率 |
| `fundingPeriod` | `28800` 秒 (8 小时) | 资金费率结算周期 |
| `maxFundingRate` | `200 bp` (2%) | 单周期资金费率上限 |
| `interestRate` | `100 bp` (1%) | 固定基础利率 |
| `pxDecimals` | `6` | 价格精度（小数位） |
| `oracleStaleThreshold` | `1800` 秒 (30 分钟) | 预言机过期阈值 |
| `vtwapTimeCapSeconds` | `3600` 秒 (1 小时) | VTWAP 时间权重上限 |

---

## 附录 B：关键函数接口

```solidity
// Pool.sol
function placeLimitOrder(bool isLong, uint256 price, uint256 size, uint256 margin) external returns (uint256 orderId);
function placeMarketOrder(bool isLong, uint256 size, uint256 margin) external returns (uint256 orderId);
function closePosition(uint256 tokenId) external;

// IndexOracle.sol
function updatePrice(uint256 newPrice) external; // onlyFactory
function updatePoolInfo(uint256 lastPrice, uint256 lastSize, uint256 timestamp) external; // onlyPool
function settleAllFunding() external; // onlyFactory, called every 8h
function getVTWAP() external view returns (uint256);
function getCurrentFundingRate() external view returns (int256);

// LiquidationEngine.sol
function liquidate(address poolAddress) external;
function registerPosition(uint256 tokenId, uint256 triggerPrice) external; // onlyPool
function removePosition(uint256 tokenId) external; // onlyPool

// Vault.sol
function deposit(uint256 amount) external;
function withdraw(uint256 amount) external;
function internalTransfer(address from, address to, uint256 amount) external; // onlyAuthorized
```

---

## 附录 C：术语表

| 术语 | 解释 |
|------|------|
| Perpetual Futures | 永续合约，无到期日的期货合约 |
| VTWAP | Volume and Time Weighted Average Price，成交量时间加权平均价 |
| fundingIdx | 资金费率全局累加器，用于高效计算仓位资金费用 |
| Order Statistics Tree | 增强红黑树，支持 O(log n) 排名查询 |
| Isolated Margin | 隔离保证金，每个仓位独立计算保证金 |
| Bankruptcy Price | 破产价格，保证金归零时对应的价格 |
| triggerPrice | 清算触发价格，低于（多头）或高于（空头）此价格触发清算 |
| Maker | 限价挂单方，提供流动性 |
| Taker | 市价吃单方，消耗流动性 |
| CEI Pattern | Checks-Effects-Interactions，Solidity 安全编程模式 |
| PnL | Profit and Loss，盈亏 |
| BASIS_POINT | 基点，1 bp = 0.01% |

---

*本白皮书为技术参考文档，不构成投资建议。智能合约存在技术风险，请在充分了解风险的基础上参与。*