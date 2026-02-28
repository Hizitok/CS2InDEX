// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {TestERC20}        from "./mocks/TestERC20.sol";
import {CS2InDEXFactory}  from "../src/Factory.sol";
import {Vault}            from "../src/Vault.sol";
import {IndexOracle}      from "../src/IndexOracle.sol";
import {Pool}             from "../src/Pool.sol";
import {positionNFT}      from "../src/PositionNFT.sol";
import {OrderTypes}       from "../src/interfaces/OrderTypes.sol";

/**
 * @title Gas Benchmark — 极端压力测试
 * @notice 随机挂1000个限价/市价单，统计 newOrder 的 gas 开销分布。
 *
 *   规则：
 *     - 价格随机 [$100, $200]（步长 $1）
 *     - 数量随机从 {10, 20, 30, 50, 100} 单位中抽取
 *     - 每 10 笔中第 10 笔改为市价单（方向随机）
 *     - 买/卖方向随机
 *     - 双方向都使用同一资金池，订单会互相撮合
 *
 *   统计维度：
 *     - min / max / avg (总体)
 *     - 每 100 笔的阶段均值（观察 BST 增长后 gas 的漂移）
 *     - 市价单 vs 限价单单独均值
 */
contract GasBenchmarkTest is Test, OrderTypes {

    // ── Contracts ────────────────────────────────────────────────
    TestERC20       public usdc;
    CS2InDEXFactory public factory;
    Vault           public vault;
    IndexOracle     public oracle;
    Pool            public pool;

    // ── Traders (轮流下单，避免单地址余额耗尽) ─────────────────
    address[4] traders;

    // ── Constants ────────────────────────────────────────────────
    uint256 constant INITIAL_PRICE  = 150e6;   // 初始 oracle 价格 $150
    uint256 constant MINT_AMOUNT    = 5_000_000e6; // 每个账户存 500 万 USDC
    uint256 constant MARGIN_PER_ORD = 1_500e6; // 每笔保证金 $1500（足够 100 units @ $200 10x）
    uint256 constant ROUNDS         = 1000;
    uint256[5] SIZES;                          // 单位量 (6 dec)

    // ── Gas stats ────────────────────────────────────────────────
    // 每 100 笔一个 checkpoint，共 10 段
    uint256[10] cpSum;    // 阶段 gas 累计
    uint256[10] cpCnt;    // 阶段成功笔数

    uint256 totalGasLimit    = type(uint256).max;
    uint256 totalGasMarket   = 0;
    uint256 marketCnt        = 0;
    uint256 limitGasSum      = 0;
    uint256 limitCnt         = 0;
    uint256 gasMin           = type(uint256).max;
    uint256 gasMax           = 0;
    uint256 successCnt       = 0;
    uint256 failCnt          = 0;

    // ── Setup ────────────────────────────────────────────────────

    function setUp() public {
        SIZES[0] = 10e6;
        SIZES[1] = 20e6;
        SIZES[2] = 30e6;
        SIZES[3] = 50e6;
        SIZES[4] = 100e6;

        traders[0] = address(0xA1);
        traders[1] = address(0xA2);
        traders[2] = address(0xA3);
        traders[3] = address(0xA4);

        usdc    = new TestERC20("USDC", "USDC", 6);
        factory = new CS2InDEXFactory(address(usdc));
        vault   = Vault(factory.vault());
        oracle  = IndexOracle(factory.oracle());

        (address poolAddr,) = factory.createPool("CS2-GlobalIndex", INITIAL_PRICE, 6);
        pool = Pool(poolAddr);

        // Feed oracle
        vm.prank(address(factory));
        oracle.updateIndexPrice(address(pool), INITIAL_PRICE);

        // Fund & deposit all traders
        for (uint i = 0; i < 4; i++) {
            usdc.mint(traders[i], MINT_AMOUNT);
            vm.prank(traders[i]);
            usdc.approve(address(vault), type(uint256).max);
            vm.prank(traders[i]);
            vault.deposit(MINT_AMOUNT);
        }
    }

    // ── Main benchmark ───────────────────────────────────────────

    function testGasBenchmark_1000Orders() public {
        console.log("\n=== Gas Benchmark: 1000 Orders ===");
        console.log("Price range: $100 - $200, Sizes: {10,20,30,50,100}");
        console.log("Rule: every 10th order is a market order (random side)");
        console.log("-------------------------------------------\n");

        for (uint256 i = 0; i < ROUNDS; i++) {
            _placeOrder(i);
        }

        _printResults();
    }

    // ── Internal helpers ─────────────────────────────────────────

    function _placeOrder(uint256 i) internal {
        // Pseudo-random from index
        bytes32 rng = keccak256(abi.encodePacked(i, uint256(0xDEADBEEF)));

        bool     isSell  = (uint8(rng[0]) & 1) == 0;
        uint256  sizeIdx = uint256(uint8(rng[1])) % 5;
        uint256  size    = SIZES[sizeIdx];
        address  trader  = traders[i % 4];

        // 价格随机 [$100, $200]，整数步长 $1
        uint256 price;
        orderType oType;

        if (i % 10 == 9) {
            // 每 10 笔第 10 笔：市价单
            oType = orderType.Market;
            price = 0;
        } else {
            oType = orderType.Limit;
            uint256 priceStep = uint256(uint8(rng[2])) % 101; // 0..100
            price = 100e6 + priceStep * 1e6;                  // $100..$200
        }

        // 检查余额够不够，不够则跳过
        if (vault.balanceOf(trader) < MARGIN_PER_ORD) {
            failCnt++;
            return;
        }

        uint256 g0 = gasleft();
        vm.prank(trader);
        try pool.newOrder(MARGIN_PER_ORD, PoolOrder({
            isSell: isSell,
            oType:  oType,
            size:   size,
            price:  price
        })) returns (OrderId) {
            uint256 g = g0 - gasleft();
            _recordGas(i, g, oType == orderType.Market);
        } catch {
            failCnt++;
        }
    }

    function _recordGas(uint256 i, uint256 g, bool isMarket) internal {
        successCnt++;

        if (g < gasMin) gasMin = g;
        if (g > gasMax) gasMax = g;

        uint256 cp = i / 100;   // checkpoint index 0..9
        cpSum[cp] += g;
        cpCnt[cp]++;

        if (isMarket) {
            totalGasMarket += g;
            marketCnt++;
        } else {
            limitGasSum += g;
            limitCnt++;
        }
    }

    function _printResults() internal view {
        uint256 totalGasAll = limitGasSum + totalGasMarket;

        console.log("=== Overall Stats ===");
        console.log("  Successful orders:", successCnt);
        console.log("  Failed orders    :", failCnt);
        console.log("  Gas min          :", gasMin);
        console.log("  Gas max          :", gasMax);
        if (successCnt > 0)
            console.log("  Gas avg (all)    :", totalGasAll / successCnt);
        if (limitCnt > 0)
            console.log("  Gas avg (limit)  :", limitGasSum / limitCnt);
        if (marketCnt > 0)
            console.log("  Gas avg (market) :", totalGasMarket / marketCnt);

        console.log("\n=== Per-100-Order Averages (BST growth effect) ===");
        for (uint256 cp = 0; cp < 10; cp++) {
            uint256 lo = cp * 100 + 1;
            uint256 hi = (cp + 1) * 100;
            if (cpCnt[cp] > 0) {
                console.log(
                    string.concat("  Orders #", _itoa(lo), "-#", _itoa(hi),
                    "  n=", _itoa(cpCnt[cp]),
                    "  avg=", _itoa(cpSum[cp] / cpCnt[cp]))
                );
            }
        }
    }

    // ── Gas breakdown diagnostic ─────────────────────────────────

    /**
     * @notice 逐步拆解 newOrder 的 gas 来源
     *
     *  newOrder 调用链：
     *    _newOrderInternal
     *      ├─ [A] internalTransfer  (vault SSTORE: 2次余额更新)
     *      ├─ [B] newNFT            (mint ERC721 + 写 Position struct 12个字段)
     *      ├─ [C] OBPx/OBSize SSTORE (2次映射写入)
     *      └─ orderMatching
     *           ├─ [D-no]  无撮合 → insert into BST
     *           └─ [D-yes] 有撮合 → matchMaking
     *                ├─ 2× getPosition (SLOAD)
     *                ├─ 2× updatePosition (12字段 SSTORE)
     *                ├─ BST remove (maker)
     *                ├─ 2× registerPosition (engine BST insert + SSTORE)
     *                ├─ (可能) 2× settlePnL (internalTransfer)
     *                └─ oracle.updatePoolInfo (SSTORE)
     */
    function testGasBreakdown() public {
        console.log("\n=== Gas Breakdown: newOrder Sub-operations ===\n");

        // ── [A] ERC20.transfer 基线 (2x SSTORE, warm slot) ──────
        usdc.mint(address(this), 2);
        uint256 g0 = gasleft();
        usdc.transfer(traders[0], 1);
        uint256 gERC20Tx = g0 - gasleft();
        console.log("[A] ERC20.transfer (2x warm SSTORE baseline) :", gERC20Tx);

        // ── [B] Full newOrder with NO match ──────────────────────
        // 第一笔挂买单，对面市场空，不撮合
        g0 = gasleft();
        vm.prank(traders[0]);
        pool.newOrder(MARGIN_PER_ORD, PoolOrder({
            isSell: false, oType: orderType.Limit,
            size: 10e6, price: 150e6
        }));
        uint256 gNoMatch = g0 - gasleft();
        console.log("[B] newOrder, NO match (1st order, BST=0)   :", gNoMatch);

        // ── [C] 再挂同侧限价单，BST 已有 1 个节点 ───────────────
        g0 = gasleft();
        vm.prank(traders[1]);
        pool.newOrder(MARGIN_PER_ORD, PoolOrder({
            isSell: false, oType: orderType.Limit,
            size: 10e6, price: 148e6
        }));
        uint256 gNoMatch2 = g0 - gasleft();
        console.log("[C] newOrder, NO match (BST=1 node)         :", gNoMatch2);

        // ── [D] 挂对侧限价单，触发一次撮合 ──────────────────────
        g0 = gasleft();
        vm.prank(traders[2]);
        pool.newOrder(MARGIN_PER_ORD, PoolOrder({
            isSell: true, oType: orderType.Limit,
            size: 10e6, price: 149e6   // 149 < 150 → 与第一笔 buy@150 匹配
        }));
        uint256 gOneMatch = g0 - gasleft();
        console.log("[D] newOrder, 1 MATCH (maker remove+settle) :", gOneMatch);

        // ── [E] 市价单，撮合剩余一笔 buy@148 ────────────────────
        g0 = gasleft();
        vm.prank(traders[3]);
        pool.newOrder(MARGIN_PER_ORD, PoolOrder({
            isSell: true, oType: orderType.Market,
            size: 10e6, price: 0
        }));
        uint256 gMarket = g0 - gasleft();
        console.log("[E] newOrder, Market (match + cancel rem)   :", gMarket);

        // ── [F] 挂 10 笔进 BST，再撮合一笔，观察 BST 深度影响 ──
        for (uint i = 0; i < 10; i++) {
            bytes32 rng = keccak256(abi.encodePacked(i, "fill"));
            bool isSell = (i % 2 == 0);
            uint256 price = isSell ? (160e6 + i * 1e6) : (130e6 - i * 1e6);
            vm.prank(traders[i % 4]);
            pool.newOrder(MARGIN_PER_ORD, PoolOrder({
                isSell: isSell, oType: orderType.Limit,
                size: 20e6, price: price
            }));
        }
        // 现在各侧 BST 约有 5 个节点，再挂一个穿叉单
        g0 = gasleft();
        vm.prank(traders[0]);
        pool.newOrder(MARGIN_PER_ORD, PoolOrder({
            isSell: false, oType: orderType.Limit,
            size: 20e6, price: 160e6   // 160 == best ask → 撮合
        }));
        uint256 gDeep = g0 - gasleft();
        console.log("[F] newOrder, match, BST each~5 nodes       :", gDeep);

        // ── Summary ───────────────────────────────────────────────
        console.log("\n--- Analysis ---");
        console.log("  NFT mint + internalTransfer + OBPx/OBSize + BST insert:");
        console.log("    (B total = everything in newOrder no-match) :", gNoMatch);
        console.log("  Incremental per BST node (C - B)           :", gNoMatch2 > gNoMatch ? gNoMatch2 - gNoMatch : 0);
        console.log("  matchMaking overhead (D - B, single match) :", gOneMatch > gNoMatch ? gOneMatch - gNoMatch : 0);
        console.log("  Market order overhead vs limit (E vs B)    :", gMarket > gNoMatch ? gMarket - gNoMatch : 0);
        console.log("  BST-5 vs BST-0 match overhead (F - D)      :", gDeep > gOneMatch ? gDeep - gOneMatch : 0);

        // Key components breakdown (approximations)
        // vault.deposit does 2 SSTOREs; internalTransfer inside newOrder also 2 SSTOREs
        // EIP-2929 warm/cold distinction matters here
        uint256 sstoreCold = 22100;
        console.log("\n--- SSTORE cost reference ---");
        console.log("  Cold SSTORE (new slot)   : 22100 gas");
        console.log("  Warm SSTORE (existing)   : 2900 gas");
        console.log("  Position struct = 10 slots (with packing) -> fresh mint ~221000 gas just for struct");
        console.log("  ERC721 owner+balance = 2 slots -> ~44200 gas");
        console.log("  OBPx + OBSize = 2 slots -> ~44200 gas");
        console.log("  BST node (3 slots: parent/left/right) -> ~66300 gas per node insert");
    }

    // Minimal uint→string for console output
    function _itoa(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 tmp = v;
        uint256 len;
        while (tmp > 0) { len++; tmp /= 10; }
        bytes memory buf = new bytes(len);
        while (v > 0) { buf[--len] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(buf);
    }
}
