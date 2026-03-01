# CS2InDEX — Roadshow Preparation Checklist

> 目标：向 VC / 基金 / 游戏公司 路演，展示一个可演示、逻辑自洽、有潜力的 Web3 衍生品协议。

---

## 状态概览

| 模块 | 现状 | 路演就绪度 |
|------|------|-----------|
| 智能合约 | 完成，内部审计通过 | ⚠️ 需外部审计 |
| 前端 | 基本可用，本地运行 | ⚠️ 需测试网部署 |
| Oracle 服务 | 可运行，单源 | ⚠️ 需多源聚合 |
| 测试覆盖 | 122 个用例通过 | ✅ 够用 |
| 白皮书 | concepts/whitepaper.md | ✅ 完成 |
| Pitch Deck | concepts/pitchDeck.md | ✅ 完成 |
| 代币经济学 | concepts/tokenomics.md | ✅ 完成 |
| 测试网演示 | 已部署 Unichain Sepolia（ChainId 1301） | ✅ 可演示 |
| 外部审计 | 未进行 | ❌ 必须有 |
| 市场分析 | 无文档 | ❌ 必须有 |
| 团队介绍 | 无 | ❌ 必须有 |
| 竞品分析 | pitchDeck.md Slide 8 | ✅ 初版 |

---

## P0 — 路演前必须完成（阻断项）

### 1. 修复生产阻断 Bug

以下两个问题会让投资人或技术评审直接否掉演示：

- [x] **Router 不可用**：`depositAndOpenPosition` 是主要用户入口，但 Router 未在 Vault 中授权
  - 已修复：`Factory.setRouter(_router)` 注册 Router 并授权至 Vault + 所有现有 Pool；新建 Pool 时自动调用 `pool.setRouter(router)`；`Router.withdraw` 改用 `vault.withdrawFor` 修复提款 msg.sender 错误；`Vault` 新增 `withdrawFor(user, to, amount)` 方法

- [x] **`emergencyCloseAllPositions` 方法体为空**：只 emit 事件，不执行任何操作
  - 已修复：实现完整逻辑——先暂停 Pool，再对传入的 position ID 数组依次在 oracle 价格执行强平；用 try/catch 跳过无效 ID，不中断批量执行

### 2. 测试网部署

- [x] 选择测试网（**Unichain Sepolia**，ChainId 1301）
- [x] 部署完整合约栈（Factory、Vault、Pool、Oracle、PositionNFT、LiquidationEngine）
- [x] 部署 Mock USDC（ERC20，含公开 mint 函数）
- [x] 配置 Oracle 服务对接测试网合约地址
- [x] 配置前端指向测试网合约（`bash scripts/sync-addresses.sh` 自动同步）
- [ ] 公开测试网地址和 faucet 链接

### 3. Pitch Deck（10-15 页 PPT）

路演核心材料，缺一不可：

- [ ] **问题**：CS2 皮肤持有者无法对冲价格下跌风险；投机者无法做空皮肤市场
- [ ] **解决方案**：链上永续合约，追踪 CS2 市场指数，支持最高 10x 杠杆
- [ ] **市场规模**：CS2 皮肤市场 ~$50-80 亿美元存量，年交易额 $XX 亿（需引用数据）
- [ ] **产品演示截图**：前端界面、开仓/平仓流程、PnL 结算
- [ ] **技术架构图**：一张简洁的系统图（Factory / Pool / Oracle / NFT）
- [ ] **商业模式**：交易手续费（Maker 0.3% / Taker 0.5%）→ 协议收益计算示例
- [ ] **竞品对比**：为什么不直接用 GMX/dYdX？（针对性场景：游戏资产，无对手方）
- [ ] **代币经济学**：治理代币、费用分配、激励方案（见下节）
- [ ] **路线图**：MVP → 主网 → L2 → 更多游戏资产（Dota2、TF2 等）
- [ ] **团队介绍**：每人一句话 + 背景（GitHub / LinkedIn）
- [ ] **融资需求**：要多少钱、用在哪、达到什么里程碑

### 4. 代币经济学设计

当前协议无代币，投资人无退出路径：

- [ ] 设计治理代币（如 $CSIDX）
  - 初始分配：团队 / 投资人 / 社区 / 国库 / 生态 占比
  - 解锁计划：团队锁仓 1 年 cliff + 3 年线性
- [ ] 协议费用分配：
  - 例：50% → 协议国库，30% → 质押者，20% → 做市商激励
- [ ] 代币用途：治理投票（添加新指数、调整参数）、质押获取费用分成
- [ ] 初始流动性计划：IDO / 私募 / LP 激励

---

## P1 — 路演质量提升（有则加分）

### 5. 白皮书（技术 + 经济学）✅

- [x] 协议机制：资金费率公式推导、清算模型、VTWAP 计算
- [x] Oracle 安全性：VTWAP 防操纵设计（min(Δt, cap) × size 权重）
- [x] 经济攻击分析：自成交操纵资金费率的成本模型
- [ ] 市场指数构成：选哪些皮肤，权重如何计算，再平衡规则
- [ ] 风险模型：极端行情下的协议偿付能力分析

### 6. 市场分析文档

- [ ] CS2 皮肤市场规模（总市值、日交易量、主要平台份额）
  - 参考：SkinFlow.gg、EsportFire、Buff163
- [ ] 目标用户群：
  - 皮肤持有者（对冲需求）
  - 加密原生交易员（新资产类别）
  - 游戏内容创作者 / 职业选手（大额持仓）
- [ ] TAM / SAM / SOM 估算
- [ ] 竞品分析矩阵：
  | 项目 | 资产类型 | 链上订单簿 | 永续合约 | CS2 支持 |
  |------|---------|-----------|---------|---------|
  | CS2InDEX | CS2 指数 | ✅ | ✅ | ✅ |
  | GMX | Crypto | ❌（AMM） | ✅ | ❌ |
  | dYdX | Crypto | ✅ | ✅ | ❌ |
  | Nifty Finance | NFT | ❌ | ❌ | ❌ |

### 7. 外部安全审计

投资人和用户的最低信任门槛：

- [ ] 联系知名审计机构（Certik / Peckshield / Trail of Bits / Code4rena）
- [ ] 至少完成一家 Code4rena 竞争审计（成本相对低，$5-20K）
- [ ] 已知问题需在审计前修复：
  - `liquidate()` 无迭代上限（gas 耗尽风险）
  - 自成交 VTWAP 操纵风险
  - `getPositionsByOwner` O(N) gas 问题

### 8. 做市商 / 初始流动性方案

链上订单簿冷启动必须解决流动性问题：

- [x] 实现网格做市算法（marketmaker/ 目录，Martingale 策略）
- [x] 做市商自动资金管理（自动 mint USDC、approve、deposit）
- [x] 测试网阶段先跑内部做市，验证 VTWAP 和资金费率计算
- [ ] 设计做市商激励（手续费减免 / 代币奖励）
- [ ] 计划启动时投入多少 USDC 作为初始流动性

---

## P2 — 长期完善（主网前）

### 9. 法律合规

- [ ] 确认运营主体注册地（开曼 / 新加坡 / BVI 基金会常见选择）
- [ ] 评估是否需要将协议完全 DAO 化以规避监管
- [ ] 用户条款：明确禁止美国/受制裁地区用户（地理封锁）
- [ ] 咨询律师：永续合约是否构成受监管金融产品（因司法管辖区不同而异）

### 10. 品牌与社区

目前 README 中的 Discord/Twitter 均为占位符：

- [ ] 注册并激活 Twitter / X 账号
- [ ] 创建 Discord 服务器（频道：公告、讨论、技术、测试网反馈）
- [ ] 发布测试网邀请，收集早期用户
- [ ] 联系 CS2 内容创作者 / KOL 进行早期推广

### 11. 技术健壮性（主网前修复）

- [x] Router 完整实现并测试 `depositAndOpenPosition`
- [x] `emergencyCloseAllPositions` 完整实现
- [ ] `liquidate()` 添加 `maxIterations` 参数
- [ ] `getPositionsByOwner` 改为链下索引 + `TheGraph` 子图
- [ ] Oracle 多源聚合（至少 3 个数据源，取中位数）
- [ ] L2 部署评估（Unichain 主网更低 gas）

---

## 演示脚本（Demo Day）

路演时的标准演示流程（约 5 分钟）：

1. **背景**（30s）：CS2 皮肤市场 $50B+，持有者无法对冲，我们解决这个问题
2. **打开前端**：展示 CS2 指数实时价格（Oracle 服务运行中）
3. **存入 USDC**：从 faucet 领取测试 USDC，存入 Vault
4. **开多仓**：挂 Limit 单买入 CS2 Global Index，展示订单簿
5. **对手方成交**：演示者 B 挂对手单（或做市脚本自动成交）
6. **展示 Position NFT**：MetaMask 中显示 NFT，说明可转让
7. **资金费率**：展示下一次结算时间和当前资金费率
8. **平仓 + PnL**：平仓，展示 USDC 结算到账
9. **一句话总结**：这是 CS2 皮肤市场的 dYdX

---

## 优先级总结

| 优先级 | 任务 | 状态 |
|--------|------|------|
| **P0-阻断** | 修复 Router + emergencyClose | ✅ 完成 |
| **P0-阻断** | 测试网部署（Unichain Sepolia） | ✅ 完成 |
| **P0-阻断** | Pitch Deck 制作 | ✅ 完成 |
| **P0-阻断** | 代币经济学设计 | ✅ 完成 |
| **P1-加分** | 白皮书 | ✅ 完成 |
| **P1-加分** | 外部审计启动 | ❌ 待启动 |
| **P1-加分** | 做市商方案 + 脚本 | ✅ 完成 |
| **P1-加分** | 市场分析文档 | ❌ 待完成 |
| **P2-主网** | 法律架构咨询 | ❌ 待启动 |
| **P2-主网** | 社区建设 | ❌ 待启动 |