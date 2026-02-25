// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {TestERC20} from "./mocks/TestERC20.sol";
import {CS2InDEXFactory} from "../src/Factory.sol";
import {Vault} from "../src/Vault.sol";
import {IndexOracle} from "../src/IndexOracle.sol";
import {Pool} from "../src/Pool.sol";
import {positionNFT} from "../src/PositionNFT.sol";
import {IPool} from "../src/interfaces/IPool.sol";
import {IEngine} from "../src/interfaces/IEngine.sol";
import {LiquidationEngine} from "../src/Liquidation.sol";
import {OrderTypes} from "../src/interfaces/OrderTypes.sol";

/**
 * @title 完整集成测试
 * @notice 从部署到交易的完整流程测试
 */
contract IntegrationTest is Test, OrderTypes {

    // Contracts
    TestERC20 public usdc;
    CS2InDEXFactory public factory;
    Vault public vault;
    IndexOracle public oracle;
    positionNFT public nft;
    Pool public pool;
    address public liquidationEngine;

    // Users
    address public owner = address(this);
    address public trader1 = address(0x1);
    address public trader2 = address(0x2);
    address public trader3 = address(0x3);

    // Constants
    uint256 constant INITIAL_PRICE = 100e6;  // $100 with 6 decimals
    uint256 constant PRICE_DECIMALS = 6;
    string constant ITEM_NAME = "AK47-Redline";

    function setUp() public {
        console.log("\n=== Integration Test Setup ===");

        // 1. Deploy ERC20 Token (USDC)
        console.log("\n1. Deploying USDC token...");
        usdc = new TestERC20("USD Coin", "USDC", 6);
        console.log("USDC deployed at:", address(usdc));

        // 2. Deploy Factory (which deploys Vault, Oracle, NFT)
        console.log("\n2. Deploying Factory...");
        factory = new CS2InDEXFactory(address(usdc));
        console.log("Factory deployed at:", address(factory));

        vault = Vault(factory.vault());
        oracle = IndexOracle(factory.oracle());
        nft = positionNFT(factory.nft());

        console.log("  - Vault:", address(vault));
        console.log("  - Oracle:", address(oracle));
        console.log("  - PositionNFT:", address(nft));


        // 3. Create Pool
        console.log("\n3. Creating pool for", ITEM_NAME);
        (address poolAddr, address engineAddr) = factory.createPool(
            ITEM_NAME,
            INITIAL_PRICE,
            PRICE_DECIMALS
        );
        pool = Pool(poolAddr);
        liquidationEngine = engineAddr;

        console.log("Pool deployed at:", address(pool));
        console.log("LiquidationEngine at:", liquidationEngine);

        // 4. Mint USDC to traders
        console.log("\n4. Minting USDC to traders...");
        usdc.mint(trader1, 100000e6); // 100k USDC
        usdc.mint(trader2, 100000e6);
        usdc.mint(trader3, 50000e6);
        console.log("Trader1 USDC balance:", usdc.balanceOf(trader1) / 1e6);
        console.log("Trader2 USDC balance:", usdc.balanceOf(trader2) / 1e6);
        console.log("Trader3 USDC balance:", usdc.balanceOf(trader3) / 1e6);

        // 5. Traders approve vault
        console.log("\n5. Traders approving Vault...");
        vm.prank(trader1);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(trader2);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(trader3);
        usdc.approve(address(vault), type(uint256).max);
        console.log("All traders approved Vault");

        // 6. Traders deposit to vault
        console.log("\n6. Traders depositing to Vault...");
        vm.prank(trader1);
        vault.deposit(50000e6);
        vm.prank(trader2);
        vault.deposit(50000e6);
        vm.prank(trader3);
        vault.deposit(25000e6);
        console.log("Trader1 Vault balance:", vault.balanceOf(trader1) / 1e6);
        console.log("Trader2 Vault balance:", vault.balanceOf(trader2) / 1e6);
        console.log("Trader3 Vault balance:", vault.balanceOf(trader3) / 1e6);

        // 7. Update oracle price (must be called by Factory since it's the owner)
        console.log("\n7. Feeding price to Oracle...");
        vm.prank(address(factory));
        oracle.updateIndexPrice(address(pool), INITIAL_PRICE);
        console.log("Oracle price set to:", oracle.oraclePrice(address(pool)) / 1e6);

        console.log("\n=== Setup Complete ===\n");
    }

    /*//////////////////////////////////////////////////////////////
                        完整交易流程测试
    //////////////////////////////////////////////////////////////*/

    function testFullTradingFlow() public {
        console.log("\n=== Full Trading Flow Test ===\n");

        // Step 1: Trader1 places limit buy order
        console.log("Step 1: Trader1 places limit buy at $95");
        vm.prank(trader1);
        OrderId buyOrderId = pool.newOrder(
            10000e6,  // 10k margin
            PoolOrder({
                isSell: false,
                oType: orderType.Limit,
                size: 1e6,  // 1 unit
                price: 95e6
            })
        );
        console.log("  Buy order ID:", OrderId.unwrap(buyOrderId));

        Position memory buyPos = nft.getPosition(buyOrderId);
        console.log("  Position status:", uint256(buyPos.status));
        console.log("  Pending size:", buyPos.pendingSize);

        // Step 2: Trader2 places limit sell order at higher price (no match)
        console.log("\nStep 2: Trader2 places limit sell at $105 (no match)");
        vm.prank(trader2);
        OrderId sellOrderId = pool.newOrder(
            10000e6,
            PoolOrder({
                isSell: true,
                oType: orderType.Limit,
                size: 1e6,
                price: 105e6
            })
        );
        console.log("  Sell order ID:", OrderId.unwrap(sellOrderId));

        // Step 3: Check orderbook
        console.log("\nStep 3: Checking orderbook...");
        (uint256 lastPrice, uint256 askPrice, uint256 bidPrice) = pool.getOrderbookInfo();
        console.log("  Last price:", lastPrice / 1e6);
        console.log("  Best ask:", askPrice / 1e6);
        console.log("  Best bid:", bidPrice / 1e6);

        // Step 4: Trader3 places market sell to match buy order
        console.log("\nStep 4: Trader3 places market sell (matches Trader1's buy)");
        vm.prank(trader3);
        OrderId marketSellId = pool.newOrder(
            5000e6,
            PoolOrder({
                isSell: true,
                oType: orderType.Market,
                size: 1e6,
                price: 0
            })
        );
        console.log("  Market sell ID:", OrderId.unwrap(marketSellId));

        // Check positions after match
        buyPos = nft.getPosition(buyOrderId);
        Position memory sellPos = nft.getPosition(marketSellId);

        console.log("  Trader1 position status:", uint256(buyPos.status));
        console.log("  Trader1 open size:", buyPos.openSize);
        console.log("  Trader3 position status:", uint256(sellPos.status));
        console.log("  Trader3 open size:", sellPos.openSize);

        assertTrue(buyPos.status == posStatus.open, "Buy position should be open");
        assertTrue(sellPos.status == posStatus.open, "Sell position should be open");

        // Step 5: Update oracle price to simulate market movement
        console.log("\nStep 5: Oracle updates price to $110");
        vm.prank(address(factory));
        oracle.updateIndexPrice(address(pool), 110e6);
        console.log("  New oracle price:", oracle.oraclePrice(address(pool)) / 1e6);

        // Step 6: Trader1 closes long position with profit
        console.log("\nStep 6: Trader1 closes long position at $108");
        vm.prank(trader1);
        pool.closePosition(
            buyOrderId,
            PoolOrder({
                isSell: true,
                oType: orderType.Limit,
                size: 1e6,
                price: 108e6
            })
        );

        buyPos = nft.getPosition(buyOrderId);
        console.log("  Position status after close order:", uint256(buyPos.status));

        // Step 7: Trader2 (who has limit sell at 105) gets matched
        console.log("\nStep 7: Checking if Trader2's sell order matched...");
        sellPos = nft.getPosition(sellOrderId);
        console.log("  Trader2 position status:", uint256(sellPos.status));
        console.log("  Trader2 open size:", sellPos.openSize);

        // Step 8: Verify final positions
        console.log("\nStep 8: Final position verification");
        console.log("  Trader1 (long) open size:", nft.getPosition(buyOrderId).openSize);
        console.log("  Trader2 (sell) open size:", nft.getPosition(sellOrderId).openSize);
        console.log("  Trader3 (short) open size:", nft.getPosition(marketSellId).openSize);

        console.log("\n=== Trading Flow Test Complete ===\n");
    }

    /*//////////////////////////////////////////////////////////////
                        价格更新测试
    //////////////////////////////////////////////////////////////*/

    function testOraclePriceUpdate() public {
        console.log("\n=== Oracle Price Update Test ===\n");

        // Initial price
        uint256 price1 = oracle.oraclePrice(address(pool));
        console.log("Initial price:", price1 / 1e6);
        assertEq(price1, INITIAL_PRICE, "Initial price should match");

        // Update price (must be called by Factory since it's the owner)
        uint256 newPrice = 120e6;
        vm.prank(address(factory));
        oracle.updateIndexPrice(address(pool), newPrice);

        uint256 price2 = oracle.oraclePrice(address(pool));
        console.log("Updated price:", price2 / 1e6);
        assertEq(price2, newPrice, "Price should be updated");

        // Pool should also see the updated price
        uint256 poolOraclePrice = pool.oraclePrice();
        console.log("Pool oracle price:", poolOraclePrice / 1e6);
        assertEq(poolOraclePrice, newPrice, "Pool should see updated oracle price");

        console.log("\n=== Oracle Test Complete ===\n");
    }

    /*//////////////////////////////////////////////////////////////
                        订单簿测试
    //////////////////////////////////////////////////////////////*/

    function testOrderbookDepth() public {
        console.log("\n=== Orderbook Depth Test ===\n");

        // Place multiple buy orders
        console.log("Placing buy orders...");
        vm.prank(trader1);
        pool.newOrder(5000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 1e6,
            price: 95e6
        }));

        vm.prank(trader2);
        pool.newOrder(5000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 1e6,
            price: 90e6
        }));

        // Place multiple sell orders
        console.log("Placing sell orders...");
        vm.prank(trader1);
        pool.newOrder(5000e6, PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: 1e6,
            price: 105e6
        }));

        vm.prank(trader2);
        pool.newOrder(5000e6, PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: 1e6,
            price: 110e6
        }));

        // Check orderbook
        (uint256 lastPrice, uint256 askPrice, uint256 bidPrice) = pool.getOrderbookInfo();

        console.log("Orderbook state:");
        console.log("  Best bid (highest buy):", bidPrice / 1e6);
        console.log("  Best ask (lowest sell):", askPrice / 1e6);
        console.log("  Spread:", (askPrice - bidPrice) / 1e6);

        assertEq(bidPrice, 95e6, "Best bid should be $95");
        assertEq(askPrice, 105e6, "Best ask should be $105");

        console.log("\n=== Orderbook Test Complete ===\n");
    }

    /*//////////////////////////////////////////////////////////////
                        资金管理测试
    //////////////////////////////////////////////////////////////*/

    function testVaultOperations() public {
        console.log("\n=== Vault Operations Test ===\n");

        // Check initial balances
        uint256 trader1Balance = vault.balanceOf(trader1);
        console.log("Trader1 initial vault balance:", trader1Balance / 1e6);

        // Place order (should lock margin in pool)
        vm.prank(trader1);
        pool.newOrder(10000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 1e6,
            price: 95e6
        }));

        uint256 trader1BalanceAfter = vault.balanceOf(trader1);
        uint256 poolBalance = vault.balanceOf(address(pool));

        console.log("Trader1 vault balance after order:", trader1BalanceAfter / 1e6);
        console.log("Pool vault balance:", poolBalance / 1e6);

        assertEq(trader1Balance - trader1BalanceAfter, 10000e6, "Margin should be transferred");
        assertEq(poolBalance, 10000e6, "Pool should receive margin");

        console.log("\n=== Vault Test Complete ===\n");
    }

    /*//////////////////////////////////////////////////////////////
                        订单取消测试
    //////////////////////////////////////////////////////////////*/

    function testOrderCancellation() public {
        console.log("\n=== Order Cancellation Test ===\n");

        // Place limit order
        vm.prank(trader1);
        OrderId orderId = pool.newOrder(10000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 1e6,
            price: 95e6
        }));

        Position memory pos = nft.getPosition(orderId);
        console.log("Order placed, status:", uint256(pos.status));
        assertTrue(pos.status == posStatus.pendingOpen, "Should be pending open");

        // Cancel order
        vm.prank(trader1);
        bool success = pool.cancelOrder(orderId);
        assertTrue(success, "Cancel should succeed");

        pos = nft.getPosition(orderId);
        console.log("After cancel, status:", uint256(pos.status));
        assertTrue(pos.status == posStatus.closed, "Should be closed");

        console.log("\n=== Cancellation Test Complete ===\n");
    }

    /*//////////////////////////////////////////////////////////////
                        部分成交测试
    //////////////////////////////////////////////////////////////*/

    function testPartialFill() public {
        console.log("\n=== Partial Fill Test ===\n");

        // Trader1 places buy for 2 units
        vm.prank(trader1);
        OrderId buyId = pool.newOrder(20000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 2e6,
            price: 100e6
        }));

        // Trader2 sells only 1 unit
        vm.prank(trader2);
        OrderId sellId = pool.newOrder(10000e6, PoolOrder({
            isSell: true,
            oType: orderType.Market,
            size: 1e6,
            price: 0
        }));

        Position memory buyPos = nft.getPosition(buyId);
        Position memory sellPos = nft.getPosition(sellId);

        console.log("Buy position:");
        console.log("  Open size:", buyPos.openSize);
        console.log("  Pending size:", buyPos.pendingSize);
        console.log("  Status:", uint256(buyPos.status));

        assertEq(buyPos.openSize, 1e6, "Should have 1 unit filled");
        assertEq(buyPos.pendingSize, 1e6, "Should have 1 unit pending");
        assertTrue(buyPos.status == posStatus.pendingOpen, "Should still be pending");

        console.log("\nSell position:");
        console.log("  Open size:", sellPos.openSize);
        console.log("  Status:", uint256(sellPos.status));

        assertEq(sellPos.openSize, 1e6, "Should have 1 unit filled");
        assertTrue(sellPos.status == posStatus.open, "Should be fully open");

        console.log("\n=== Partial Fill Test Complete ===\n");
    }

    /*//////////////////////////////////////////////////////////////
                        部分成交后取消测试
    //////////////////////////////////////////////////////////////*/

    function testPartialFillThenCancel() public {
        console.log("\n=== Partial Fill Then Cancel Test ===\n");

        uint256 initialBalance = vault.balanceOf(trader1);
        console.log("Trader1 initial vault balance:", initialBalance / 1e6);

        // Trader1 places buy for 2 units with 20k margin
        vm.prank(trader1);
        OrderId buyId = pool.newOrder(20000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 2e6,
            price: 100e6
        }));

        uint256 afterOrderBalance = vault.balanceOf(trader1);
        console.log("After order, vault balance:", afterOrderBalance / 1e6);
        assertEq(initialBalance - afterOrderBalance, 20000e6, "Should lock 20k margin");

        // Trader2 sells only 1 unit (half fill)
        vm.prank(trader2);
        pool.newOrder(10000e6, PoolOrder({
            isSell: true,
            oType: orderType.Market,
            size: 1e6,
            price: 0
        }));

        Position memory buyPos = nft.getPosition(buyId);
        console.log("\nAfter partial fill:");
        console.log("  Open size:", buyPos.openSize);
        console.log("  Pending size:", buyPos.pendingSize);
        assertEq(buyPos.openSize, 1e6, "Should have 1 unit filled");
        assertEq(buyPos.pendingSize, 1e6, "Should have 1 unit still pending");

        // Cancel the remaining unfilled portion
        vm.prank(trader1);
        pool.cancelOrder(buyId);

        uint256 afterCancelBalance = vault.balanceOf(trader1);
        console.log("\nAfter cancel:");
        console.log("  Vault balance:", afterCancelBalance / 1e6);

        // Should refund approximately 50% of remaining margin (after fees were deducted)
        // Note: Maker fee = 0.3% of match amount = 100 USDC * 0.003 = 0.3 USDC
        // So remaining margin = 20000 - 300 = 19999.7 USDC (actually 19999.85 with rounding)
        // Refund = 19999.85 * 1/2 ≈ 9999.925 USDC
        uint256 refunded = afterCancelBalance - afterOrderBalance;
        console.log("  Refunded amount:", refunded / 1e6);

        // Allow small deviation due to fees (should be close to 10k but slightly less)
        assertTrue(refunded >= 9999e6 && refunded <= 10000e6, "Should refund approximately half");
        assertTrue(refunded < 10000e6, "Should be less than 10k due to fees");

        buyPos = nft.getPosition(buyId);
        console.log("  Final status:", uint256(buyPos.status));
        console.log("  Remaining margin:", buyPos.openMargin / 1e6);

        assertTrue(buyPos.status == posStatus.open, "Should be open (has filled portion)");
        assertEq(buyPos.pendingSize, 0, "Pending size should be 0");
        assertEq(buyPos.openSize, 1e6, "Should still have 1 unit open");

        // The remaining margin should also be approximately 10k (half of original minus half of fees)
        assertTrue(buyPos.openMargin >= 9999e6 && buyPos.openMargin <= 10000e6,
            "Remaining margin should be approximately 10k");

        console.log("\n=== Partial Fill Cancel Test Complete ===\n");
    }

    /*//////////////////////////////////////////////////////////////
                        资金费率结算测试
    //////////////////////////////////////////////////////////////*/

    function testFundingRateSettlement() public {
        console.log("\n=== Funding Rate Settlement Test ===\n");

        // Record initial funding index
        uint256 initialFundingIdx = pool.fundingIdx();
        console.log("Initial funding index:", initialFundingIdx);

        // Step 1: Create some trading activity to generate premium index data
        console.log("\nStep 1: Creating trading activity...");

        // Trader1 buys at 102 (higher than oracle 100) - premium exists
        vm.prank(trader1);
        OrderId buyId1 = pool.newOrder(10000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 1e6,
            price: 102e6
        }));

        // Trader2 sells at 102
        vm.prank(trader2);
        pool.newOrder(10000e6, PoolOrder({
            isSell: true,
            oType: orderType.Market,
            size: 1e6,
            price: 0
        }));

        console.log("  First trade executed at 102 USDC");
        console.log("  Oracle price:", oracle.oraclePrice(address(pool)) / 1e6);
        console.log("  Last traded price:", pool.getLastPrice() / 1e6);

        // Step 2: Update oracle price to keep data valid (within 2 min window)
        console.log("\nStep 2: Updating oracle price...");
        vm.warp(block.timestamp + 1 minutes);
        vm.prank(address(factory));
        oracle.updateIndexPrice(address(pool), 100e6);

        // Step 3: More trades to accumulate VTWAP data
        console.log("\nStep 3: More trading activity...");
        vm.warp(block.timestamp + 30 seconds);

        vm.prank(trader1);
        pool.newOrder(10000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 1e6,
            price: 103e6
        }));

        vm.prank(trader2);
        pool.newOrder(10000e6, PoolOrder({
            isSell: true,
            oType: orderType.Market,
            size: 1e6,
            price: 0
        }));

        console.log("  Second trade executed at 103 USDC");

        // Check accumulated data
        (uint64 lastTradeTs, uint128 avgVTWAP) = oracle.getPoolsStats(address(pool));
        console.log("\nAccumulated data:");
        console.log("  Last trade timestamp:", lastTradeTs);
        console.log("  Avg VTWAP:", avgVTWAP / 1e6);

        // Step 4: Calculate funding rate before settlement
        console.log("\nStep 4: Calculating funding rate...");
        (int128 avgVTWAPDiff, int128 interestRate, int128 fundingRate) =
            oracle.calculateFundingRate(address(pool));

        console.log("  Avg VTWAP Diff (bp):", avgVTWAPDiff);
        console.log("  Interest Rate (bp):", interestRate);
        console.log("  Funding Rate (bp):", fundingRate);

        // Step 5: Try to settle before period ends (should fail)
        console.log("\nStep 5: Attempting early settlement (should fail)...");
        vm.expectRevert("Settlement period not reached");
        vm.prank(address(factory));
        oracle.applyFundingRate(address(pool));
        console.log("  Early settlement correctly rejected");

        // Step 6: Warp time to after settlement period (8 hours)
        console.log("\nStep 6: Fast forward 8 hours...");
        vm.warp(block.timestamp + 8 hours);

        // Step 7: Apply funding rate
        console.log("\nStep 7: Applying funding rate...");
        vm.prank(address(factory));
        oracle.applyFundingRate(address(pool));

        uint256 newFundingIdx = pool.fundingIdx();
        console.log("  New funding index:", newFundingIdx);
        console.log("  Funding index changed:", newFundingIdx != initialFundingIdx);

        // Verify funding index changed
        assertTrue(newFundingIdx != initialFundingIdx, "Funding index should have changed");

        // Step 8: Verify accumulators are reset after settlement
        console.log("\nStep 8: Verifying stats reset...");
        (uint64 newLastTradeTs, uint128 newAvgVTWAP) = oracle.getPoolsStats(address(pool));
        console.log("  New last trade timestamp:", newLastTradeTs);
        console.log("  New avg VTWAP:", newAvgVTWAP);
        // After settlement lastTradeTime is reset to block.timestamp (non-zero)
        assertTrue(newLastTradeTs > 0, "lastTradeTime should be set after settlement");
        assertEq(newAvgVTWAP, 0, "Avg VTWAP should reset to 0");

        // Step 9: Open new position after funding rate change
        console.log("\nStep 9: Opening new position after funding rate change...");
        vm.prank(trader3);
        OrderId buyId2 = pool.newOrder(10000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 1e6,
            price: 100e6
        }));

        vm.prank(trader2);
        pool.newOrder(10000e6, PoolOrder({
            isSell: true,
            oType: orderType.Market,
            size: 1e6,
            price: 0
        }));

        // Compare funding indices
        Position memory oldPos = nft.getPosition(buyId1);
        Position memory newPos = nft.getPosition(buyId2);

        console.log("\nPosition funding indices:");
        console.log("  Old position (opened before funding):", oldPos.openFundingIdx);
        console.log("  New position (opened after funding):", newPos.openFundingIdx);

        // The new position's funding index should include the new fundingIdx
        // Note: openFundingIdx = fillSize * fundingIdx, so they will be different
        assertTrue(oldPos.openFundingIdx != newPos.openFundingIdx,
            "Positions should have different funding indices");

        console.log("\n=== Funding Rate Settlement Test Complete ===\n");
    }

    /*//////////////////////////////////////////////////////////////
                        清算引擎测试
    //////////////////////////////////////////////////////////////*/

    function testLiquidationEngine() public {
        console.log("\n=== Liquidation Engine Test ===\n");

        LiquidationEngine engine = LiquidationEngine(liquidationEngine);

        // Step 1: Open leveraged positions
        // 10 units at $100 = $1000 notional, $200 margin = 5x leverage
        // Trigger at ~$84 (20% margin remaining), Bankrupt at ~$80
        console.log("Step 1: Opening leveraged positions (5x)...");
        console.log("  Margin: 200 USDC, Size: 10 units, Price: 100 USDC");

        vm.prank(trader1);
        OrderId longId = pool.newOrder(200e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 10e6,
            price: 100e6
        }));

        vm.prank(trader2);
        OrderId shortId = pool.newOrder(200e6, PoolOrder({
            isSell: true,
            oType: orderType.Market,
            size: 10e6,
            price: 0
        }));

        // Both positions should be open now
        Position memory longPos = nft.getPosition(longId);
        Position memory shortPos = nft.getPosition(shortId);
        console.log("  Long status:", uint256(longPos.status));
        console.log("  Short status:", uint256(shortPos.status));
        assertTrue(longPos.status == posStatus.open, "Long should be open");
        assertTrue(shortPos.status == posStatus.open, "Short should be open");

        console.log("  Long openMargin:", longPos.openMargin / 1e6, "USDC");
        console.log("  Short openMargin:", shortPos.openMargin / 1e6, "USDC");

        // Step 2: Verify engine registered both positions
        console.log("\nStep 2: Verifying engine queue...");
        (uint256 longCount, uint256 shortCount) = engine.getQueueInfo();
        console.log("  Long queue:", longCount);
        console.log("  Short queue:", shortCount);
        assertEq(longCount, 1, "Should have 1 long in queue");
        assertEq(shortCount, 1, "Should have 1 short in queue");

        // Step 3: Check trigger prices
        console.log("\nStep 3: Checking trigger prices...");
        uint256 longTrigger = engine.getTriggerPx(longId);
        uint256 shortTrigger = engine.getTriggerPx(shortId);
        console.log("  Long trigger price:", longTrigger / 1e6, "USDC");
        console.log("  Short trigger price:", shortTrigger / 1e6, "USDC");
        assertTrue(longTrigger < 100e6, "Long trigger should be below entry");
        assertTrue(shortTrigger > 100e6, "Short trigger should be above entry");

        // Step 4: At current price ($100), neither should be liquidatable
        console.log("\nStep 4: Checking liquidatability at $100...");
        assertFalse(engine.isLiquidatable(longId), "Long should NOT be liquidatable at $100");
        assertFalse(engine.isLiquidatable(shortId), "Short should NOT be liquidatable at $100");
        console.log("  Neither position is liquidatable at current price");

        // Step 5: Provide buy-side liquidity for liquidation fill
        console.log("\nStep 5: Trader3 places buy order at $82 (liquidity for liquidation)...");
        vm.prank(trader3);
        OrderId liqBuyId = pool.newOrder(1000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 10e6,
            price: 82e6
        }));

        // Step 6: Crash oracle price to $80 (below long trigger ~$84)
        console.log("\nStep 6: Crashing oracle price to $80...");
        vm.prank(address(factory));
        oracle.updateIndexPrice(address(pool), 80e6);
        console.log("  Oracle price:", oracle.oraclePrice(address(pool)) / 1e6, "USDC");

        // Step 7: Check liquidatability after crash
        console.log("\nStep 7: Checking liquidatability at $80...");
        bool longLiquidatable = engine.isLiquidatable(longId);
        bool shortLiquidatable = engine.isLiquidatable(shortId);
        console.log("  Long liquidatable:", longLiquidatable);
        console.log("  Short liquidatable:", shortLiquidatable);
        assertTrue(longLiquidatable, "Long SHOULD be liquidatable at $80");
        assertFalse(shortLiquidatable, "Short should NOT be liquidatable at $80");

        // Step 8: Execute liquidation
        console.log("\nStep 8: Executing liquidation...");
        engine.liquidate();

        // Step 9: Verify long position was liquidated
        console.log("\nStep 9: Verifying results...");
        longPos = nft.getPosition(longId);
        shortPos = nft.getPosition(shortId);

        console.log("  Long status after liquidation:", uint256(longPos.status));
        console.log("  Long openSize:", longPos.openSize);
        console.log("  Short status:", uint256(shortPos.status));
        console.log("  Short openSize:", shortPos.openSize);

        // Long should be closed/settled (filled against trader3's buy)
        assertTrue(
            longPos.status == posStatus.closed || longPos.status == posStatus.settled,
            "Long should be closed or settled after liquidation"
        );

        // Short should still be open
        assertTrue(shortPos.status == posStatus.open, "Short should still be open");

        // Step 10: Verify engine queue updated
        // Long queue has 1: trader3's new long position (bought the liquidation)
        // Short queue has 1: trader2's original short
        (longCount, shortCount) = engine.getQueueInfo();
        console.log("  Long queue after liquidation:", longCount);
        console.log("  Short queue after liquidation:", shortCount);
        assertEq(longCount, 1, "Long queue should have trader3's new long");
        assertEq(shortCount, 1, "Short queue should still have 1");

        // Step 11: Check vault balances
        console.log("\nStep 11: Vault balances after liquidation...");
        console.log("  Trader1 (liquidated long):", vault.balanceOf(trader1) / 1e6, "USDC");
        console.log("  Trader2 (short, profitable):", vault.balanceOf(trader2) / 1e6, "USDC");
        console.log("  Trader3 (bought liquidation):", vault.balanceOf(trader3) / 1e6, "USDC");

        console.log("\n=== Liquidation Engine Test Complete ===\n");
    }

    /*//////////////////////////////////////////////////////////////
                  资金费率累积导致强制平仓测试
    //////////////////////////////////////////////////////////////*/

    function testFundingRateLiquidation() public {
        console.log("\n=== Funding Rate Liquidation Test ===\n");

        LiquidationEngine engine = LiquidationEngine(liquidationEngine);

        // Create 5 extra test accounts
        address alice   = address(0xA);  // Long, high leverage  → will be liquidated
        address bob     = address(0xB);  // Short counterparty
        address charlie = address(0xC);  // Long, low leverage   → should survive
        address dave    = address(0xD);  // Short counterparty
        address eve     = address(0xE);  // Liquidity provider for liquidation fill

        // Fund and deposit for all accounts
        address[5] memory traders = [alice, bob, charlie, dave, eve];
        for (uint i = 0; i < traders.length; i++) {
            usdc.mint(traders[i], 100000e6);
            vm.prank(traders[i]);
            usdc.approve(address(vault), type(uint256).max);
            vm.prank(traders[i]);
            vault.deposit(50000e6);
        }
        console.log("5 test accounts funded (50k USDC each)");

        // Increase funding rate cap so we can trigger liquidation faster
        // Cap = 500 bp (5%), Floor = -500 bp
        vm.prank(address(factory));
        oracle.setFundingRateLimits(500, -500);
        console.log("Funding rate cap set to 5% per period");

        // ---- Step 1: Open leveraged positions ----
        console.log("\nStep 1: Opening positions...");

        // Alice: Long 10 units @ $100, margin $250 (~4x leverage)
        // Trigger ~$80, needs ~$20 price-equivalent funding to liquidate
        vm.prank(alice);
        OrderId aliceId = pool.newOrder(250e6, PoolOrder({
            isSell: false, oType: orderType.Limit,
            size: 10e6, price: 100e6
        }));
        vm.prank(bob);
        pool.newOrder(250e6, PoolOrder({
            isSell: true, oType: orderType.Market,
            size: 10e6, price: 0
        }));

        // Charlie: Long 5 units @ $100, margin $500 (~1x leverage, very safe)
        vm.prank(charlie);
        OrderId charlieId = pool.newOrder(500e6, PoolOrder({
            isSell: false, oType: orderType.Limit,
            size: 5e6, price: 100e6
        }));
        vm.prank(dave);
        pool.newOrder(500e6, PoolOrder({
            isSell: true, oType: orderType.Market,
            size: 5e6, price: 0
        }));

        Position memory alicePos = nft.getPosition(aliceId);
        Position memory charliePos = nft.getPosition(charlieId);
        console.log("  Alice  (4x long): margin =", alicePos.openMargin / 1e6, "USDC");
        console.log("  Charlie (1x long): margin =", charliePos.openMargin / 1e6, "USDC");

        uint256 aliceTrigger = engine.getTriggerPx(aliceId);
        uint256 charlieTrigger = engine.getTriggerPx(charlieId);
        console.log("  Alice trigger price:", aliceTrigger / 1e6, "USDC");
        console.log("  Charlie trigger price:", charlieTrigger / 1e6, "USDC");

        // ---- Step 2: Accumulate funding over multiple periods ----
        console.log("\nStep 3: Accumulating funding over multiple periods...");
        console.log("  (Positive premium = longs pay shorts)\n");

        uint256 fundingPeriods = 0;
        bool aliceLiquidated = false;

        // Run funding periods until Alice gets liquidated
        (aliceLiquidated, fundingPeriods) = _runFundingLoop(engine, aliceId);

        assertTrue(aliceLiquidated, "Alice should be liquidatable after funding accumulation");

        // ---- Step 3: Eve provides liquidity at bankruptcy-beating price ----
        console.log("\nStep 3: Eve places buy order at $98 for liquidation fill...");
        vm.prank(eve);
        pool.newOrder(1000e6, PoolOrder({
            isSell: false, oType: orderType.Limit,
            size: 10e6, price: 98e6
        }));

        // ---- Step 4: Execute liquidation ----
        console.log("\nStep 4: Executing liquidation...");
        assertFalse(engine.isLiquidatable(charlieId), "Charlie should NOT be liquidatable");
        console.log("  Charlie is safe (low leverage)");

        engine.liquidate();
        console.log("  Liquidation executed!");

        // ---- Step 5: Verify results ----
        _verifyFundingLiquidationResults(aliceId, charlieId, fundingPeriods);
    }

    function _verifyFundingLiquidationResults(
        OrderId aliceId, OrderId charlieId, uint256 fundingPeriods
    ) internal {
        console.log("\nStep 5: Verifying results...");
        Position memory aPos = nft.getPosition(aliceId);
        Position memory cPos = nft.getPosition(charlieId);

        console.log("  Alice status:", uint256(aPos.status), "openSize:", aPos.openSize);
        console.log("  Charlie status:", uint256(cPos.status), "openSize:", cPos.openSize);

        assertTrue(
            aPos.status == posStatus.closed || aPos.status == posStatus.settled,
            "Alice should be liquidated"
        );
        assertTrue(cPos.status == posStatus.open, "Charlie should still be open");

        console.log("\nStep 6: Final vault balances...");
        console.log("  Alice  (liquidated):", vault.balanceOf(address(0xA)) / 1e6, "USDC");
        console.log("  Bob    (short):", vault.balanceOf(address(0xB)) / 1e6, "USDC");
        console.log("  Charlie (safe):", vault.balanceOf(address(0xC)) / 1e6, "USDC");
        console.log("  Dave   (short):", vault.balanceOf(address(0xD)) / 1e6, "USDC");
        console.log("  Eve    (buyer):", vault.balanceOf(address(0xE)) / 1e6, "USDC");
        console.log("\n  Funding periods to liquidation:", fundingPeriods);
        console.log("\n=== Funding Rate Liquidation Test Complete ===\n");
    }

    /// @dev Helper: run funding loop until Alice is liquidatable
    function _runFundingLoop(LiquidationEngine engine, OrderId aliceId)
        internal
        returns (bool liquidated, uint256 periods)
    {
        for (uint i = 0; i < 12; i++) {
            _runFundingPeriod();
            periods++;

            console.log("  Period", periods);
            console.log("    FundingIdx:", pool.fundingIdx() / 1e6, "USDC equiv");
            console.log("    Alice trigger:", engine.getTriggerPx(aliceId) / 1e6, "USDC");

            if (engine.isLiquidatable(aliceId)) {
                console.log("    >>> Alice is now LIQUIDATABLE! <<<");
                return (true, periods);
            }
            console.log("    Alice liquidatable: false");
        }
        return (false, periods);
    }

    /// @dev Helper: create premium trade + warp + apply funding rate
    function _runFundingPeriod() internal {
        // Update oracle price (must be within 2 min window for VTWAP)
        vm.prank(address(factory));
        oracle.updateIndexPrice(address(pool), 100e6);

        vm.warp(block.timestamp + 30 seconds);

        // Trade at premium ($110 vs oracle $100 = 10% premium)
        vm.prank(trader1);
        pool.newOrder(10000e6, PoolOrder({
            isSell: false, oType: orderType.Limit,
            size: 1e6, price: 110e6
        }));
        vm.prank(trader2);
        pool.newOrder(10000e6, PoolOrder({
            isSell: true, oType: orderType.Market,
            size: 1e6, price: 0
        }));

        // Warp past settlement period and apply
        vm.warp(block.timestamp + 8 hours);
        vm.prank(address(factory));
        oracle.applyFundingRate(address(pool));
    }
}
