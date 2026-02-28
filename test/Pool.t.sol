// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";
import {IPool} from "../src/interfaces/IPool.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {IPosition} from "../src/interfaces/IPosition.sol";
import {IEngine} from "../src/interfaces/IEngine.sol";
import {OrderTypes} from "../src/interfaces/OrderTypes.sol";

/**
 * @title Pool Test Suite
 * @notice Comprehensive tests for Pool contract functionality
 */
contract PoolTest is Test, OrderTypes {
    Pool public pool;
    MockVault public vault;
    MockPosition public positionNFT;
    MockOracle public oracle;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);
    MockEngine public mockEngine;

    uint256 constant INITIAL_PRICE = 50000e6; // $50k with 6 decimals
    uint256 constant PRICE_DECIMALS = 6;

    function setUp() public {
        // Deploy mocks
        vault = new MockVault();
        positionNFT = new MockPosition();
        oracle = new MockOracle();

        // Deploy pool
        pool = new Pool(
            address(vault),
            address(positionNFT),
            address(oracle),
            PRICE_DECIMALS,
            INITIAL_PRICE,
            "BTC/USD Pool"
        );

        // Set pool authorization in position NFT
        positionNFT.setPool(address(pool), true);

        // Deploy and set engine
        mockEngine = new MockEngine();
        pool.setEngine(address(mockEngine));

        // Fund users in vault
        vault.mint(user1, 100000e6); // 100k USDC
        vault.mint(user2, 100000e6);
        vault.mint(user3, 50000e6);

        // Update oracle price
        vm.prank(address(oracle));
        pool.updateOraclePrice(INITIAL_PRICE);
    }

    /*//////////////////////////////////////////////////////////////
                        ORDER CREATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testNewOrder_LimitBuy() public {
        uint256 margin = 10000e6; // 10k USDC margin
        uint256 size = 1e6; // 1 BTC (size in same decimals as price)
        uint256 price = 49000e6; // Buy at $49k

        PoolOrder memory order = PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: size,
            price: price
        });

        vm.prank(user1);
        OrderId orderId = pool.newOrder(margin, order);

        // Verify position was created
        Position memory pos = positionNFT.getPosition(orderId);
        assertEq(pos.isShort, false, "Should be long");
        assertEq(pos.status == posStatus.pendingOpen, true, "Should be pending");
        assertEq(pos.openMargin, margin, "Margin should match");
        assertEq(pos.pendingSize, size, "Size should match");

        // Verify vault transfer
        assertEq(vault.balanceOf(user1), 90000e6, "User1 balance should decrease");
        assertEq(vault.balanceOf(address(pool)), margin, "Pool should receive margin");
    }

    function testNewOrder_LimitSell() public {
        uint256 margin = 10000e6;
        uint256 size = 1e6;
        uint256 price = 51000e6; // Sell at $51k

        PoolOrder memory order = PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: size,
            price: price
        });

        vm.prank(user2);
        OrderId orderId = pool.newOrder(margin, order);

        Position memory pos = positionNFT.getPosition(orderId);
        assertEq(pos.isShort, true, "Should be short");
        assertEq(pos.status == posStatus.pendingOpen, true, "Should be pending");
    }

    function testNewOrder_MarketMatch() public {
        // User1 places limit buy at 50k
        uint256 margin1 = 10000e6;
        uint256 size1 = 1e6;
        uint256 price1 = 50000e6;

        PoolOrder memory buyOrder = PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: size1,
            price: price1
        });

        vm.prank(user1);
        OrderId buyId = pool.newOrder(margin1, buyOrder);

        // User2 places market sell - should match
        uint256 margin2 = 10000e6;
        uint256 size2 = 1e6;

        PoolOrder memory sellOrder = PoolOrder({
            isSell: true,
            oType: orderType.Market,
            size: size2,
            price: 0 // Market order
        });

        vm.prank(user2);
        OrderId sellId = pool.newOrder(margin2, sellOrder);

        // Verify both positions are now open
        Position memory buyPos = positionNFT.getPosition(buyId);
        Position memory sellPos = positionNFT.getPosition(sellId);

        assertEq(buyPos.status == posStatus.open, true, "Buy should be open");
        assertEq(sellPos.status == posStatus.open, true, "Sell should be open");
        assertEq(buyPos.openSize, size1, "Buy size should match");
        assertEq(sellPos.openSize, size2, "Sell size should match");

        // Verify last price was updated
        assertEq(pool.getLastPrice(), price1, "Last price should be match price");
    }

    function testNewOrder_PartialFill() public {
        // User1 places small limit buy
        uint256 margin1 = 5000e6;
        uint256 size1 = 0.5e6; // 0.5 BTC
        uint256 price1 = 50000e6;

        PoolOrder memory buyOrder = PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: size1,
            price: price1
        });

        vm.prank(user1);
        OrderId buyId = pool.newOrder(margin1, buyOrder);

        // User2 places larger limit sell - partial match
        uint256 margin2 = 10000e6;
        uint256 size2 = 1e6; // 1 BTC
        uint256 price2 = 49000e6; // Lower price, will match

        PoolOrder memory sellOrder = PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: size2,
            price: price2
        });

        vm.prank(user2);
        OrderId sellId = pool.newOrder(margin2, sellOrder);

        // Verify buy order fully filled
        Position memory buyPos = positionNFT.getPosition(buyId);
        assertEq(buyPos.openSize, size1, "Buy fully filled");
        assertEq(buyPos.status == posStatus.open, true, "Buy should be open");

        // Verify sell order partially filled
        Position memory sellPos = positionNFT.getPosition(sellId);
        assertEq(sellPos.openSize, size1, "Sell partially filled");
        assertEq(sellPos.pendingSize, size2 - size1, "Remaining pending");
        assertEq(sellPos.status == posStatus.pendingOpen, true, "Should still be pending");
    }

    function testNewOrder_RevertPriceOverflow() public {
        uint256 margin = 10000e6;
        uint256 size = 1e6;
        uint256 invalidPrice = INITIAL_PRICE * 3; // Too high

        PoolOrder memory order = PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: size,
            price: invalidPrice
        });

        vm.prank(user1);
        vm.expectRevert(IPool.PxOverflow.selector);
        pool.newOrder(margin, order);
    }

    function testNewOrder_RevertLeverageOverflow() public {
        uint256 margin = 1000e6; // Small margin
        uint256 size = 10e6; // Large size = high leverage
        uint256 price = 50000e6;

        PoolOrder memory order = PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: size,
            price: price
        });

        vm.prank(user1);
        vm.expectRevert(IPool.LeverageOverflow.selector);
        pool.newOrder(margin, order);
    }

    /*//////////////////////////////////////////////////////////////
                        ORDER CANCELLATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelOrder_PendingOpen() public {
        // Create limit order
        uint256 margin = 10000e6;
        uint256 size = 1e6;
        uint256 price = 51000e6;

        PoolOrder memory order = PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: size,
            price: price
        });

        vm.prank(user1);
        OrderId orderId = pool.newOrder(margin, order);

        // Cancel order
        vm.prank(user1);
        bool success = pool.cancelOrder(orderId);

        assertTrue(success, "Cancel should succeed");

        // Verify position is closed
        Position memory pos = positionNFT.getPosition(orderId);
        assertEq(pos.status == posStatus.closed, true, "Should be closed");
        assertEq(pos.pendingSize, 0, "Pending size should be 0");
    }

    function testCancelOrder_PendingClose() public {
        // First create and fill a position
        uint256 margin = 10000e6;
        uint256 size = 1e6;
        uint256 buyPrice = 50000e6;

        // User1 limit buy
        PoolOrder memory buyOrder = PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: size,
            price: buyPrice
        });

        vm.prank(user1);
        OrderId buyId = pool.newOrder(margin, buyOrder);

        // User2 market sell to fill
        vm.prank(user2);
        PoolOrder memory sellOrder = PoolOrder({
            isSell: true,
            oType: orderType.Market,
            size: size,
            price: 0
        });
        pool.newOrder(margin, sellOrder);

        // Now user1 tries to close with limit order
        PoolOrder memory closeOrder = PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: size,
            price: 51000e6 // Higher than any buy orders
        });

        vm.prank(user1);
        pool.closePosition(buyId, closeOrder);

        // Verify it's pending close
        Position memory pos = positionNFT.getPosition(buyId);
        assertEq(pos.status == posStatus.pendingClose, true, "Should be pending close");

        // Cancel the close order
        vm.prank(user1);
        bool success = pool.cancelOrder(buyId);

        assertTrue(success, "Cancel should succeed");

        // Verify back to open status
        pos = positionNFT.getPosition(buyId);
        assertEq(pos.status == posStatus.open, true, "Should be open again");
    }

    function testCancelOrder_RevertNotAuthorized() public {
        // User1 creates order
        PoolOrder memory order = PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 1e6,
            price: 49000e6
        });

        vm.prank(user1);
        OrderId orderId = pool.newOrder(10000e6, order);

        // User2 tries to cancel - should fail
        vm.prank(user2);
        vm.expectRevert(IPool.NotAuthorized.selector);
        pool.cancelOrder(orderId);
    }

    /*//////////////////////////////////////////////////////////////
                        POSITION CLOSING TESTS
    //////////////////////////////////////////////////////////////*/

    function testClosePosition_Success() public {
        // Setup: Create and fill a long position
        uint256 margin = 10000e6;
        uint256 size = 1e6;

        // User1 buy
        PoolOrder memory buyOrder = PoolOrder({
            isSell: false,
            oType: orderType.Market,
            size: size,
            price: 50000e6
        });

        // First need a sell order to match against
        vm.prank(user3);
        pool.newOrder(margin, PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: size,
            price: 50000e6
        }));

        vm.prank(user1);
        OrderId longId = pool.newOrder(margin, buyOrder);

        // Verify position is open
        Position memory pos = positionNFT.getPosition(longId);
        assertEq(pos.status == posStatus.open, true, "Should be open");

        // Close position
        PoolOrder memory closeOrder = PoolOrder({
            isSell: true, // Long closes with sell
            oType: orderType.Limit,
            size: size,
            price: 51000e6
        });

        vm.prank(user1);
        OrderId closeId = pool.closePosition(longId, closeOrder);

        assertEq(OrderId.unwrap(closeId), OrderId.unwrap(longId), "Should return same ID");

        // Verify position is pending close
        pos = positionNFT.getPosition(longId);
        assertEq(pos.status == posStatus.pendingClose, true, "Should be pending close");
    }

    function testClosePosition_RevertWrongDirection() public {
        // Create long position
        vm.prank(user3);
        pool.newOrder(10000e6, PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: 1e6,
            price: 50000e6
        }));

        vm.prank(user1);
        OrderId longId = pool.newOrder(10000e6, PoolOrder({
            isSell: false,
            oType: orderType.Market,
            size: 1e6,
            price: 50000e6
        }));

        // Try to close with wrong direction (buy instead of sell)
        PoolOrder memory wrongClose = PoolOrder({
            isSell: false, // Wrong! Should be true for long
            oType: orderType.Limit,
            size: 1e6,
            price: 49000e6
        });

        vm.prank(user1);
        vm.expectRevert(IPool.InvalidStatus.selector);
        pool.closePosition(longId, wrongClose);
    }

    function testClosePosition_PartialClose() public {
        // Create full position
        uint256 size = 2e6; // 2 BTC

        vm.prank(user3);
        pool.newOrder(20000e6, PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: size,
            price: 50000e6
        }));

        vm.prank(user1);
        OrderId longId = pool.newOrder(20000e6, PoolOrder({
            isSell: false,
            oType: orderType.Market,
            size: size,
            price: 50000e6
        }));

        // Close only half
        PoolOrder memory partialClose = PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: 1e6, // Only 1 BTC
            price: 51000e6
        });

        vm.prank(user1);
        pool.closePosition(longId, partialClose);

        Position memory pos = positionNFT.getPosition(longId);
        assertEq(pos.status == posStatus.pendingClose, true, "Should be pending close");
    }

    /*//////////////////////////////////////////////////////////////
                        PNL SETTLEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testSettlePnL_Profit() public {
        uint256 margin = 10000e6;
        uint256 size = 1e6;

        // Open long at 50k
        vm.prank(user3);
        pool.newOrder(margin, PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: size,
            price: 50000e6
        }));

        vm.prank(user1);
        OrderId longId = pool.newOrder(margin, PoolOrder({
            isSell: false,
            oType: orderType.Market,
            size: size,
            price: 50000e6
        }));

        // Close at 52k (profit)
        vm.prank(user2);
        pool.newOrder(margin, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: size,
            price: 52000e6
        }));

        vm.prank(user1);
        pool.closePosition(longId, PoolOrder({
            isSell: true,
            oType: orderType.Market,
            size: size,
            price: 52000e6
        }));

        // Position should auto-settle if fully closed
        Position memory pos = positionNFT.getPosition(longId);

        // If not auto-settled, manually settle
        if (pos.status == posStatus.closed) {
            uint256 balanceBefore = vault.balanceOf(user1);

            vm.prank(user1);
            pool.settlePnL(longId);

            uint256 balanceAfter = vault.balanceOf(user1);

            // Should receive margin + profit - fees
            assertTrue(balanceAfter > balanceBefore, "Should receive funds");
            assertTrue(balanceAfter >= margin, "Should at least get margin back on profit");
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateOraclePrice() public {
        uint256 newPrice = 51000e6;

        vm.prank(address(oracle));
        pool.updateOraclePrice(newPrice);

        assertEq(pool.oraclePrice(), newPrice, "Oracle price should update");
    }

    function testUpdateOraclePrice_RevertNotOracle() public {
        vm.prank(user1);
        vm.expectRevert(IPool.InvalidOracle.selector);
        pool.updateOraclePrice(51000e6);
    }

    function testUpdateFundingIndex() public {
        uint256 newFunding = 1 << 127;

        vm.prank(address(oracle));
        pool.updateFundingIndex(newFunding);

        assertEq(pool.fundingIdx(), newFunding, "Funding index should update");
    }

    function testSetEngine() public {
        address newEngine = address(0xABC);

        pool.setEngine(newEngine);

        assertEq(pool.engine(), newEngine, "Engine should update");
    }

    function testSetEngine_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(); // Ownable error
        pool.setEngine(address(0x123));
    }

    function testCollectFees() public {
        // First generate some fees by matching orders
        vm.prank(user3);
        pool.newOrder(10000e6, PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: 1e6,
            price: 50000e6
        }));

        vm.prank(user1);
        pool.newOrder(10000e6, PoolOrder({
            isSell: false,
            oType: orderType.Market,
            size: 1e6,
            price: 50000e6
        }));

        // Collect fees
        address feeCollector = address(0xFEE);
        uint256 balanceBefore = vault.balanceOf(feeCollector);

        pool.collectFees(feeCollector);

        uint256 balanceAfter = vault.balanceOf(feeCollector);
        assertTrue(balanceAfter > balanceBefore, "Should collect fees");
    }

    function testForceLiquidate() public {
        // Create position
        vm.prank(user3);
        pool.newOrder(10000e6, PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: 1e6,
            price: 50000e6
        }));

        vm.prank(user1);
        OrderId longId = pool.newOrder(10000e6, PoolOrder({
            isSell: false,
            oType: orderType.Market,
            size: 1e6,
            price: 50000e6
        }));

        // Engine liquidates
        PoolOrder memory liquidateOrder = PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: 1e6,
            price: 48000e6 // Bankruptcy price
        });

        vm.prank(address(mockEngine));
        pool.forceLiquidate(longId, liquidateOrder);

        Position memory pos = positionNFT.getPosition(longId);
        assertEq(pos.status == posStatus.liquidating, true, "Should be liquidating");
    }

    function testForceLiquidate_RevertNotEngine() public {
        // Try to liquidate without being engine
        vm.prank(user1);
        vm.expectRevert(IPool.NotAuthorized.selector);
        pool.forceLiquidate(OrderId.wrap(1), PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: 1e6,
            price: 48000e6
        }));
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetLastPrice() public {
        assertEq(pool.getLastPrice(), INITIAL_PRICE, "Should return initial price");

        // Place matching orders
        vm.prank(user1);
        pool.newOrder(10000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 1e6,
            price: 51000e6
        }));

        vm.prank(user2);
        pool.newOrder(10000e6, PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: 1e6,
            price: 50000e6
        }));

        // Last price should be updated to match price
        uint256 lastPrice = pool.getLastPrice();
        assertTrue(lastPrice == 50000e6 || lastPrice == 51000e6, "Should update on match");
    }

    function testGetOrderbookInfo() public {
        // Place buy and sell orders
        vm.prank(user1);
        pool.newOrder(10000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 1e6,
            price: 49000e6
        }));

        vm.prank(user2);
        pool.newOrder(10000e6, PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: 1e6,
            price: 51000e6
        }));

        (uint256 lastPrice, uint256 askPrice, uint256 bidPrice) = pool.getOrderbookInfo();

        assertEq(lastPrice, INITIAL_PRICE, "Last price should match");
        assertEq(askPrice, 51000e6, "Ask should be sell order");
        assertEq(bidPrice, 49000e6, "Bid should be buy order");
    }

    function testMaxLeverage() public view {
        assertEq(pool.maxLeverage(), 1000, "Max leverage should be 10x (1000/100)");
    }

    function testOracle() public view {
        assertEq(pool.oracle(), address(oracle), "Should return oracle address");
    }

    function testVault() public view {
        assertEq(pool.vault(), address(vault), "Should return vault address");
    }

    function testPositionNFT() public view {
        assertEq(pool.positionNFT(), address(positionNFT), "Should return position NFT address");
    }

    /*//////////////////////////////////////////////////////////////
                        DEPTH CHART TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetDepth_Empty() public view {
        (
            uint256[] memory askPrices,
            uint256[] memory askSizes,
            uint256[] memory bidPrices,
            uint256[] memory bidSizes
        ) = pool.getDepth(5);

        assertEq(askPrices.length, 5, "Ask array length should be nLevels");
        assertEq(bidPrices.length, 5, "Bid array length should be nLevels");
        for (uint256 i = 0; i < 5; i++) {
            assertEq(askPrices[i], 0, "Empty book: ask price should be 0");
            assertEq(askSizes[i],  0, "Empty book: ask size should be 0");
            assertEq(bidPrices[i], 0, "Empty book: bid price should be 0");
            assertEq(bidSizes[i],  0, "Empty book: bid size should be 0");
        }
    }

    function testGetDepth_MultiLevel() public {
        // --- Asks (sell orders, isSell=true, price > lastPrice so no match) ---
        // Level 1: 51k — two orders summing to 3e6
        vm.prank(user2);
        pool.newOrder(20000e6, PoolOrder({ isSell: true, oType: orderType.Limit, size: 2e6, price: 51000e6 }));
        vm.prank(user3);
        pool.newOrder(10000e6, PoolOrder({ isSell: true, oType: orderType.Limit, size: 1e6, price: 51000e6 }));
        // Level 2: 52k — one order of 2e6
        vm.prank(user2);
        pool.newOrder(20000e6, PoolOrder({ isSell: true, oType: orderType.Limit, size: 2e6, price: 52000e6 }));

        // --- Bids (buy orders, isSell=false, price < lastPrice so no match) ---
        // Level 1: 49k — two orders summing to 3e6
        vm.prank(user1);
        pool.newOrder(20000e6, PoolOrder({ isSell: false, oType: orderType.Limit, size: 2e6, price: 49000e6 }));
        vm.prank(user1);
        pool.newOrder(10000e6, PoolOrder({ isSell: false, oType: orderType.Limit, size: 1e6, price: 49000e6 }));
        // Level 2: 48k — one order of 2e6
        vm.prank(user1);
        pool.newOrder(20000e6, PoolOrder({ isSell: false, oType: orderType.Limit, size: 2e6, price: 48000e6 }));

        (
            uint256[] memory askPrices,
            uint256[] memory askSizes,
            uint256[] memory bidPrices,
            uint256[] memory bidSizes
        ) = pool.getDepth(5);

        // Asks: best ask first (ascending)
        assertEq(askPrices[0], 51000e6, "Ask level 0 price should be 51k");
        assertEq(askSizes[0],  3e6,     "Ask level 0 size: 2e6+1e6=3e6");
        assertEq(askPrices[1], 52000e6, "Ask level 1 price should be 52k");
        assertEq(askSizes[1],  2e6,     "Ask level 1 size should be 2e6");
        assertEq(askPrices[2], 0,       "Ask level 2 should be empty");
        assertEq(askSizes[2],  0,       "Ask level 2 size should be 0");

        // Bids: best bid first (descending)
        assertEq(bidPrices[0], 49000e6, "Bid level 0 price should be 49k");
        assertEq(bidSizes[0],  3e6,     "Bid level 0 size: 2e6+1e6=3e6");
        assertEq(bidPrices[1], 48000e6, "Bid level 1 price should be 48k");
        assertEq(bidSizes[1],  2e6,     "Bid level 1 size should be 2e6");
        assertEq(bidPrices[2], 0,       "Bid level 2 should be empty");
        assertEq(bidSizes[2],  0,       "Bid level 2 size should be 0");
    }

    function testGetDepth_NLevelsCap() public {
        // Place 3 distinct ask price levels
        vm.prank(user2);
        pool.newOrder(10000e6, PoolOrder({ isSell: true, oType: orderType.Limit, size: 1e6, price: 51000e6 }));
        vm.prank(user2);
        pool.newOrder(10000e6, PoolOrder({ isSell: true, oType: orderType.Limit, size: 1e6, price: 52000e6 }));
        vm.prank(user2);
        pool.newOrder(10000e6, PoolOrder({ isSell: true, oType: orderType.Limit, size: 1e6, price: 53000e6 }));

        // Request only 2 levels — should cap at level 51k and 52k
        (
            uint256[] memory askPrices,
            uint256[] memory askSizes,
            uint256[] memory bidPrices,
            uint256[] memory bidSizes
        ) = pool.getDepth(2);

        assertEq(askPrices.length, 2, "Should return exactly nLevels entries");
        assertEq(askPrices[0], 51000e6, "Level 0 should be best ask");
        assertEq(askPrices[1], 52000e6, "Level 1 should be second best ask");
        assertEq(bidPrices.length, 2, "Bid array length should equal nLevels");
        // No bids placed
        assertEq(bidPrices[0], 0, "No bids: should be 0");
        assertEq(bidSizes[0],  0, "No bids: size should be 0");

        // Verify third level (53k) is NOT returned even though it exists
        // (nLevels=2 caps output)
        assertEq(askSizes[1], 1e6, "Only first two levels visible");
    }

    /*//////////////////////////////////////////////////////////////
                        PAUSABLE TESTS
    //////////////////////////////////////////////////////////////*/

    function testPause_BlocksNewOrder() public {
        pool.pause();
        assertTrue(pool.paused(), "Pool should be paused");

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        pool.newOrder(10000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 1e6,
            price: 49000e6
        }));
    }

    function testPause_AllowsCancel() public {
        // Place limit order while unpaused
        vm.prank(user1);
        OrderId orderId = pool.newOrder(10000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 1e6,
            price: 49000e6
        }));

        // Pause — cancel must still work so user can recover margin
        pool.pause();

        vm.prank(user1);
        bool success = pool.cancelOrder(orderId);
        assertTrue(success, "Cancel should succeed while paused");
    }

    function testUnpause_RestoresNewOrder() public {
        pool.pause();
        pool.unpause();
        assertFalse(pool.paused(), "Pool should be unpaused");

        // Placing an order should succeed again
        vm.prank(user1);
        OrderId orderId = pool.newOrder(10000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 1e6,
            price: 49000e6
        }));
        assertTrue(OrderId.unwrap(orderId) != 0, "Order should be created after unpause");
    }

    function testPause_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(); // Ownable: caller is not the owner
        pool.pause();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // setRouter / newOrderFor
    // ─────────────────────────────────────────────────────────────────────────

    function testSetRouter() public {
        address routerAddr = address(0xBEEF);
        pool.setRouter(routerAddr);
        assertEq(pool.router(), routerAddr, "router should be updated");
    }

    function testSetRouter_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        pool.setRouter(address(0xBEEF));
    }

    function testNewOrderFor_Success() public {
        address routerAddr = address(0xBEEF);
        pool.setRouter(routerAddr);
        // setUp already funded user1 with 100000e6

        vm.prank(routerAddr);
        OrderId posId = pool.newOrderFor(user1, 10000e6, PoolOrder({
            isSell: false,
            oType:  orderType.Limit,
            size:   1e6,
            price:  49000e6
        }));

        assertTrue(OrderId.unwrap(posId) != 0, "posId must be non-zero");
        // NFT must be owned by the actual trader, not the router
        assertEq(positionNFT.ownerOf(OrderId.unwrap(posId)), user1, "NFT owner should be trader");
        // Margin deducted from trader's vault balance
        assertLt(vault.balances(user1), 100000e6, "Margin should be locked");
    }

    function testNewOrderFor_RevertNotRouter() public {
        // router is address(0) by default — any call from non-router reverts
        vault.mint(user1, 100000e6);
        vm.prank(user1);
        vm.expectRevert();
        pool.newOrderFor(user1, 10000e6, PoolOrder({
            isSell: false,
            oType:  orderType.Limit,
            size:   1e6,
            price:  49000e6
        }));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // emergencyCloseAllPositions
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Helper: open a matched long/short pair using setUp-funded balances
    function _openMatchedPair(uint256 fillPrice)
        internal
        returns (OrderId longId, OrderId shortId)
    {
        vm.prank(user1);
        longId = pool.newOrder(20000e6, PoolOrder({
            isSell: false, oType: orderType.Limit, size: 1e6, price: fillPrice
        }));

        vm.prank(user2);
        shortId = pool.newOrder(20000e6, PoolOrder({
            isSell: true, oType: orderType.Limit, size: 1e6, price: fillPrice
        }));
        // After matching both are posStatus.open
    }

    function testEmergencyCloseAllPositions_PausesAndCloses() public {
        uint256 fillPrice = INITIAL_PRICE; // 50 000e6

        (OrderId longId,) = _openMatchedPair(fillPrice);

        // Place a counter-party buy order so the emergency sell can fill
        vault.mint(user3, 100000e6);
        vm.prank(user3);
        pool.newOrder(20000e6, PoolOrder({
            isSell: false, oType: orderType.Limit, size: 1e6, price: fillPrice
        }));

        // Emergency close the long position
        OrderId[] memory toClose = new OrderId[](1);
        toClose[0] = longId;
        pool.emergencyCloseAllPositions(toClose);

        // Pool must be paused
        assertTrue(pool.paused(), "Pool should be paused after emergency close");

        // Long position must be closed or settled
        Position memory pos = positionNFT.getPosition(longId);
        assertTrue(
            pos.status == posStatus.closed || pos.status == posStatus.settled,
            "Long position should be closed/settled"
        );
    }

    function testEmergencyCloseAllPositions_SkipsNonOpen() public {
        // ID 0 returns zero-struct (pendingOpen) — must be skipped, not reverted
        OrderId[] memory toClose = new OrderId[](1);
        toClose[0] = OrderId.wrap(0);

        pool.emergencyCloseAllPositions(toClose); // must not revert

        assertTrue(pool.paused(), "Pool should still be paused even if IDs were skipped");
    }

    function testEmergencyCloseAllPositions_RevertNotOwner() public {
        OrderId[] memory toClose = new OrderId[](0);
        vm.prank(user1);
        vm.expectRevert();
        pool.emergencyCloseAllPositions(toClose);
    }

    function testForceLiquidateAsOwner_RevertNotSelf() public {
        vm.prank(user1);
        vm.expectRevert("Only self");
        pool.forceLiquidateAsOwner(OrderId.wrap(1), PoolOrder({
            isSell: true, oType: orderType.Limit, size: 1e6, price: INITIAL_PRICE
        }));
    }
}

/*//////////////////////////////////////////////////////////////
                        MOCK CONTRACTS
//////////////////////////////////////////////////////////////*/

contract MockVault is IVault {
    mapping(address => uint256) public balances;

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
    }

    function internalTransfer(address from, address to, uint256 amount) external {
        require(balances[from] >= amount, "Insufficient balance");
        balances[from] -= amount;
        balances[to] += amount;
    }

    function depositFor(address beneficiary, uint256 amount) external {
        balances[beneficiary] += amount;
    }

    function deposit(uint256 amount) external {
        balances[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
    }

    function withdrawTo(address to, uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
    }

    function withdrawFor(address user, address to, uint256 amount) external {
        require(balances[user] >= amount, "Insufficient balance");
        balances[user] -= amount;
        balances[to] += amount;
    }

    function balanceOf(address user) external view returns (uint256) {
        return balances[user];
    }

    // Pause stubs — MockVault is never actually paused in tests
    function pause() external {}
    function unpause() external {}
    function paused() external pure returns (bool) { return false; }
}

contract MockPosition is IPosition {
    uint256 private tokenIdCounter;
    mapping(uint256 => Position) private positions;
    mapping(uint256 => address) private owners;
    mapping(address => bool) private authorizedPools;
    mapping(uint256 => address) private _pools;

    function setPool(address pool, bool authorized) external {
        authorizedPools[pool] = authorized;
    }
    function getPool(OrderId id) external view returns (address) {
        return _pools[OrderId.unwrap(id)];
    }


    function newNFT(
        PoolOrder calldata pOrder,
        address owner,
        uint256 margin
    ) external returns (OrderId posId) {
        require(authorizedPools[msg.sender], "Not authorized pool");

        tokenIdCounter++;
        posId = OrderId.wrap(tokenIdCounter);

        owners[tokenIdCounter] = owner;

        _pools[tokenIdCounter]  = msg.sender;
        positions[tokenIdCounter] = Position({
            isShort: pOrder.isSell,
            status: posStatus.pendingOpen,
            openMargin: margin,
            pendingSize: pOrder.size,
            openSize: 0,
            closeSize: 0,
            openAmount: 0,
            closeAmount: 0,
            openFundingIdx: 0,
            closeFundingIdx: 0
        });
    }

    function getPosition(OrderId posId) external view returns (Position memory) {
        return positions[OrderId.unwrap(posId)];
    }

    function updatePosition(OrderId posId, Position memory pos) external returns (bool) {
        require(authorizedPools[msg.sender], "Not authorized pool");
        positions[OrderId.unwrap(posId)] = pos;
        return true;
    }

    function getOpenTick(OrderId posId) external view returns (uint256) {
        return positions[OrderId.unwrap(posId)].openAmount /
               positions[OrderId.unwrap(posId)].openSize;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return owners[tokenId];
    }

    function settlePosition(OrderId posId) external {
        require(authorizedPools[msg.sender], "Not authorized pool");
        positions[OrderId.unwrap(posId)].status = posStatus.settled;
    }

    function getPositionsByOwner(address owner)
        external
        view
        returns (uint256[] memory tokenIds, Position[] memory posArr)
    {
        uint256 count = 0;
        for (uint256 i = 1; i <= tokenIdCounter; i++) {
            if (owners[i] == owner) count++;
        }

        tokenIds = new uint256[](count);
        posArr   = new Position[](count);
        uint256 index = 0;
        for (uint256 i = 1; i <= tokenIdCounter; i++) {
            if (owners[i] == owner) {
                tokenIds[index] = i;
                posArr[index]   = positions[i];
                index++;
            }
        }
    }

    function totalSupply() external view returns (uint256) {
        return tokenIdCounter;
    }

    function tokenURI(uint256) external pure returns (string memory) {
        return "";
    }

    function isAuthorized(OrderId oID, address user) external view returns (bool) {
        return owners[OrderId.unwrap(oID)] == user;
    }

    function isAuthorizedPool(address pool) external view returns (bool) {
        return authorizedPools[pool];
    }
}

contract MockOracle {
    // updatePoolInfo is called by Pool.matchMaking after every fill
    function updatePoolInfo(uint256, uint256) external {}
}

contract MockEngine is IEngine {
    // Pool calls these during matching / settlement
    function registerPosition(OrderId) external {}
    function removePosition(OrderId) external {}
    function updatePositionInfo(OrderId) external {}
    // Anyone can trigger liquidations; no-op in mock
    function liquidate() external {}
    // View stubs
    function getTriggerPx(OrderId) external pure returns (uint256) { return 0; }
    function isLiquidatable(OrderId) external pure returns (bool) { return false; }
}
