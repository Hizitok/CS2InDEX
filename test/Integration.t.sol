// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Base.t.sol";
import {IPosition} from "../src/interfaces/IPosition.sol";

/**
 * @title IntegrationTest
 * @notice End-to-end integration tests for full trading workflows
 */
contract IntegrationTest is BaseTest {

    Pool public pool;
    CS2IndexOracle public oracle;
    positionNFT public nft;

    function setUp() public override {
        super.setUp();

        // Deploy pool
        (address _pool, address _oracle, address _nft) = _deployPool("AK47-Redline", AK47_INITIAL_PRICE);
        pool = Pool(_pool);
        oracle = CS2IndexOracle(_oracle);
        nft = positionNFT(_nft);

        // Set oracle for liquidation
        liquidationEngine.setPoolOracle(address(pool), address(oracle));
        oracle.addPriceFeeder(owner);

        // Deposit to vault
        _depositToVault(alice, 10_000e6);
        _depositToVault(bob, 10_000e6);
        _depositToVault(carol, 10_000e6);

        // Fund insurance
        vm.startPrank(owner);
        usdc.mint(owner, 10_000e6);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(10_000e6);
        liquidationEngine.depositInsuranceFund(5_000e6);
        vm.stopPrank();
    }

    function test_FullTradingCycle_Profit() public {
        // 1. Alice opens long position at $500
        PoolOrder memory aliceOpen = _createLongOrder(10, 50000, 1000e6);
        vm.prank(alice);
        OrderId aliceOrderId = pool.newOrder(aliceOpen);

        // 2. Bob matches with short
        PoolOrder memory bobOpen = _createShortOrder(10, 50000, 1000e6);
        vm.prank(bob);
        OrderId bobOrderId = pool.newOrder(bobOpen);

        // 3. Price increases to $510
        oracle.updatePrice(51000);
        pool.updateOraclePrice(51000);

        // 4. Alice closes at profit
        PoolOrder memory carolBuy = _createLongOrder(10, 51000, 1000e6);
        vm.prank(carol);
        pool.newOrder(carolBuy);

        PoolOrder memory aliceClose = _createShortOrder(10, 51000, 0);
        vm.prank(alice);
        pool.closePosition(aliceOrderId, aliceClose);

        // 5. Verify Alice made profit
        uint256 aliceBalance = vault.balanceOf(alice);
        // Alice started with 10000e6, should now have more after profit
        assertGt(aliceBalance, 9500e6);
    }

    function test_FullTradingCycle_Loss() public {
        // 1. Alice opens long at $500
        PoolOrder memory aliceOpen = _createLongOrder(10, 50000, 1000e6);
        vm.prank(alice);
        OrderId aliceOrderId = pool.newOrder(aliceOpen);

        // 2. Bob matches
        PoolOrder memory bobOpen = _createShortOrder(10, 50000, 1000e6);
        vm.prank(bob);
        pool.newOrder(bobOpen);

        // 3. Price decreases to $490
        oracle.updatePrice(49000);
        pool.updateOraclePrice(49000);

        // 4. Alice closes at loss
        PoolOrder memory carolBuy = _createLongOrder(10, 49000, 1000e6);
        vm.prank(carol);
        pool.newOrder(carolBuy);

        PoolOrder memory aliceClose = _createShortOrder(10, 49000, 0);
        vm.prank(alice);
        pool.closePosition(aliceOrderId, aliceClose);

        // 5. Verify Alice lost money
        uint256 aliceBalance = vault.balanceOf(alice);
        assertLt(aliceBalance, 9500e6);
    }

    function test_FullLiquidationFlow() public {
        // 1. Alice opens 5x leveraged long
        PoolOrder memory aliceOpen = _createLongOrder(100, 50000, 1000e6);
        vm.prank(alice);
        OrderId aliceOrderId = pool.newOrder(aliceOpen);

        // 2. Bob matches with short
        PoolOrder memory bobOpen = _createShortOrder(100, 50000, 5000e6);
        vm.prank(bob);
        pool.newOrder(bobOpen);

        // 3. Price drops 15%
        uint256 newPrice = 42500;
        oracle.updatePrice(newPrice);

        // 4. Position becomes liquidatable
        (bool liquidatable, ) = liquidationEngine.checkLiquidatable(address(pool), aliceOrderId);
        assertTrue(liquidatable);

        // 5. Carol liquidates
        uint256 carolBalanceBefore = vault.balanceOf(carol);
        vm.prank(carol);
        liquidationEngine.liquidate(address(pool), aliceOrderId);

        // 6. Verify liquidation
        Position memory pos = IPosition(address(nft)).getPosition(aliceOrderId);
        assertTrue(pos.status == posStatus.forceClose);

        // 7. Verify Carol received liquidation reward
        uint256 carolBalanceAfter = vault.balanceOf(carol);
        assertGt(carolBalanceAfter, carolBalanceBefore);
    }

    function test_MultiplePositions_SameUser() public {
        // Alice opens multiple positions
        PoolOrder memory order1 = _createLongOrder(5, 50000, 500e6);
        vm.prank(alice);
        OrderId orderId1 = pool.newOrder(order1);

        PoolOrder memory order2 = _createLongOrder(10, 50500, 1000e6);
        vm.prank(alice);
        OrderId orderId2 = pool.newOrder(order2);

        // Bob matches both
        PoolOrder memory bobOrder1 = _createShortOrder(5, 50000, 500e6);
        vm.prank(bob);
        pool.newOrder(bobOrder1);

        PoolOrder memory bobOrder2 = _createShortOrder(10, 50500, 1000e6);
        vm.prank(bob);
        pool.newOrder(bobOrder2);

        // Check Alice owns both positions
        assertEq(nft.ownerOf(OrderId.unwrap(orderId1)), alice);
        assertEq(nft.ownerOf(OrderId.unwrap(orderId2)), alice);
        assertEq(nft.balanceOf(alice), 2);
    }

    function test_OrderBook_PriceTimeMatching() public {
        // Bob places buy at $500
        PoolOrder memory bobOrder = _createLongOrder(10, 50000, 1000e6);
        vm.prank(bob);
        pool.newOrder(bobOrder);

        // Carol places buy at $505
        PoolOrder memory carolOrder = _createLongOrder(10, 50500, 1000e6);
        vm.prank(carol);
        pool.newOrder(carolOrder);

        // Alice sells at market (should match Carol first - better price)
        PoolOrder memory aliceOrder = _createMarketOrder(true, 10, 1000e6);
        vm.prank(alice);
        OrderId aliceOrderId = pool.newOrder(aliceOrder);

        // Verify matched with Carol
        Position memory alicePos = IPosition(address(nft)).getPosition(aliceOrderId);
        assertEq(alicePos.openAmount, 10 * 50500);
    }

    function test_FeeCollection_MultipleTradesAggregation() public {
        // Multiple trades
        for (uint256 i = 0; i < 3; i++) {
            PoolOrder memory buyOrder = _createLongOrder(5, 50000, 500e6);
            vm.prank(bob);
            pool.newOrder(buyOrder);

            PoolOrder memory sellOrder = _createShortOrder(5, 50000, 500e6);
            vm.prank(alice);
            pool.newOrder(sellOrder);
        }

        // Check fees accumulated
        (, , uint256 fees, , ) = pool.getPoolInfo();
        assertGt(fees, 0);

        // Owner collects fees
        uint256 ownerBalanceBefore = vault.balanceOf(owner);
        pool.collectFees(owner);
        uint256 ownerBalanceAfter = vault.balanceOf(owner);

        assertGt(ownerBalanceAfter, ownerBalanceBefore);
        assertEq(ownerBalanceAfter - ownerBalanceBefore, fees);
    }

    function test_PositionNFT_Transfer() public {
        // Alice opens position
        PoolOrder memory openOrder = _createLongOrder(10, 50000, 1000e6);
        vm.prank(alice);
        OrderId orderId = pool.newOrder(openOrder);

        // Bob matches
        PoolOrder memory bobOrder = _createShortOrder(10, 50000, 1000e6);
        vm.prank(bob);
        pool.newOrder(bobOrder);

        uint256 tokenId = OrderId.unwrap(orderId);

        // Alice transfers position NFT to Carol
        vm.prank(alice);
        nft.transferFrom(alice, carol, tokenId);

        // Verify Carol owns it now
        assertEq(nft.ownerOf(tokenId), carol);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(carol), 1);

        // Carol can now close the position
        PoolOrder memory closeOrder = _createShortOrder(10, 50000, 0);

        PoolOrder memory buyToMatch = _createLongOrder(10, 50000, 1000e6);
        vm.prank(bob);
        pool.newOrder(buyToMatch);

        vm.prank(carol); // Carol closes, not Alice
        pool.closePosition(orderId, closeOrder);
    }

    function test_MultiPool_Isolated() public {
        // Deploy another pool
        (address awpPool, address awpOracle, ) = _deployPool("AWP-Dragon Lore", AWP_INITIAL_PRICE);

        // Alice trades in both pools
        PoolOrder memory ak47Order = _createLongOrder(10, 50000, 1000e6);
        vm.prank(alice);
        pool.newOrder(ak47Order);

        PoolOrder memory awpOrder = _createLongOrder(1, 1500000, 3000e6);
        vm.prank(alice);
        Pool(awpPool).newOrder(awpOrder);

        // Verify positions in different pools
        uint256 aliceBalance = vault.balanceOf(alice);
        assertLt(aliceBalance, 10_000e6 - 1000e6 - 3000e6);
    }
}
