// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Base.t.sol";
import {IPosition} from "../src/interfaces/IPosition.sol";

contract PoolTest is BaseTest {

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

        // Deposit to vault
        _depositToVault(alice, 10_000e6);
        _depositToVault(bob, 10_000e6);
    }

    function test_NewOrder_Long() public {
        PoolOrder memory order = _createLongOrder(10, 50000, 1000e6);

        vm.prank(alice);
        OrderId orderId = pool.newOrder(order);

        // Check position created
        Position memory pos = IPosition(address(nft)).getPosition(orderId);
        assertEq(pos.positionID, 1);
        assertEq(pos.isShort, false);
        assertEq(pos.pendingSize, 10);
        assertEq(pos.openMargin, 1000e6);
        assertTrue(pos.status == posStatus.pendingOpen);
    }

    function test_NewOrder_Short() public {
        PoolOrder memory order = _createShortOrder(10, 50000, 1000e6);

        vm.prank(alice);
        OrderId orderId = pool.newOrder(order);

        Position memory pos = IPosition(address(nft)).getPosition(orderId);
        assertTrue(pos.isShort);
    }

    function test_NewOrder_RevertLeverageTooHigh() public {
        // Size * Price > Margin * 6
        PoolOrder memory order = _createLongOrder(100, 50000, 100e6);

        vm.prank(alice);
        vm.expectRevert("Leverage Overflow");
        pool.newOrder(order);
    }

    function test_OrderMatching_FullFill() public {
        // Bob places buy limit order
        PoolOrder memory buyOrder = _createLongOrder(10, 50000, 1000e6);
        vm.prank(bob);
        OrderId bobOrderId = pool.newOrder(buyOrder);

        // Alice places sell market order
        PoolOrder memory sellOrder = _createMarketOrder(true, 10, 1000e6);
        vm.prank(alice);
        OrderId aliceOrderId = pool.newOrder(sellOrder);

        // Check both positions are now open
        Position memory bobPos = IPosition(address(nft)).getPosition(bobOrderId);
        Position memory alicePos = IPosition(address(nft)).getPosition(aliceOrderId);

        assertTrue(bobPos.status == posStatus.open);
        assertTrue(alicePos.status == posStatus.open);
        assertEq(bobPos.openSize, 10);
        assertEq(alicePos.openSize, 10);
        assertEq(bobPos.pendingSize, 0);
        assertEq(alicePos.pendingSize, 0);
    }

    function test_OrderMatching_PartialFill() public {
        // Bob places buy order for 10
        PoolOrder memory buyOrder = _createLongOrder(10, 50000, 1000e6);
        vm.prank(bob);
        OrderId bobOrderId = pool.newOrder(buyOrder);

        // Alice places sell order for 15
        PoolOrder memory sellOrder = _createMarketOrder(true, 15, 1500e6);
        vm.prank(alice);
        OrderId aliceOrderId = pool.newOrder(sellOrder);

        // Bob's order fully filled
        Position memory bobPos = IPosition(address(nft)).getPosition(bobOrderId);
        assertTrue(bobPos.status == posStatus.open);
        assertEq(bobPos.openSize, 10);

        // Alice's order partially filled
        Position memory alicePos = IPosition(address(nft)).getPosition(aliceOrderId);
        assertTrue(alicePos.status == posStatus.pendingOpen);
        assertEq(alicePos.openSize, 10);
        assertEq(alicePos.pendingSize, 5);
    }

    function test_ClosePosition() public {
        // Alice opens long position
        PoolOrder memory openOrder = _createLongOrder(10, 50000, 1000e6);
        vm.prank(alice);
        OrderId orderId = pool.newOrder(openOrder);

        // Bob places buy order to match alice's close
        PoolOrder memory bobOrder = _createLongOrder(10, 51000, 1000e6);
        vm.prank(bob);
        pool.newOrder(bobOrder);

        // Alice closes position with sell
        PoolOrder memory closeOrder = _createShortOrder(10, 51000, 0);
        vm.prank(alice);
        pool.closePosition(orderId, closeOrder);

        // Position should be closed
        Position memory pos = IPosition(address(nft)).getPosition(orderId);
        assertTrue(pos.status == posStatus.closed || pos.status == posStatus.pendingClose);
    }

    function test_ClosePosition_RevertNotOwner() public {
        // Alice opens position
        PoolOrder memory openOrder = _createLongOrder(10, 50000, 1000e6);
        vm.prank(alice);
        OrderId orderId = pool.newOrder(openOrder);

        // Bob tries to close Alice's position
        PoolOrder memory closeOrder = _createShortOrder(10, 50000, 0);
        vm.prank(bob);
        vm.expectRevert("Not owner");
        pool.closePosition(orderId, closeOrder);
    }

    function test_ClosePosition_RevertWrongDirection() public {
        // Alice opens long position
        PoolOrder memory openOrder = _createLongOrder(10, 50000, 1000e6);
        vm.prank(alice);
        OrderId orderId = pool.newOrder(openOrder);

        // Try to close with same direction (long)
        PoolOrder memory wrongCloseOrder = _createLongOrder(10, 50000, 0);
        vm.prank(alice);
        vm.expectRevert("Invalid close direction");
        pool.closePosition(orderId, wrongCloseOrder);
    }

    function test_CancelOrder() public {
        // Alice places limit order
        PoolOrder memory order = _createLongOrder(10, 50000, 1000e6);
        vm.prank(alice);
        OrderId orderId = pool.newOrder(order);

        // Cancel it
        vm.prank(alice);
        pool.cancelOrder(orderId);

        Position memory pos = IPosition(address(nft)).getPosition(orderId);
        assertEq(pos.pendingSize, 0);
    }

    function test_FeesCollected() public {
        // Trade happens
        PoolOrder memory buyOrder = _createLongOrder(10, 50000, 1000e6);
        vm.prank(bob);
        pool.newOrder(buyOrder);

        PoolOrder memory sellOrder = _createMarketOrder(true, 10, 1000e6);
        vm.prank(alice);
        pool.newOrder(sellOrder);

        // Check fees collected
        (, , uint256 fees, , ) = pool.getPoolInfo();
        assertGt(fees, 0);
    }

    function test_CollectFees_OnlyOwner() public {
        // Generate some fees
        PoolOrder memory buyOrder = _createLongOrder(10, 50000, 1000e6);
        vm.prank(bob);
        pool.newOrder(buyOrder);

        PoolOrder memory sellOrder = _createMarketOrder(true, 10, 1000e6);
        vm.prank(alice);
        pool.newOrder(sellOrder);

        // Owner can collect
        pool.collectFees(owner);

        // Non-owner cannot
        vm.prank(alice);
        vm.expectRevert();
        pool.collectFees(alice);
    }

    function test_GetPoolInfo() public {
        (uint256 lastPrice, uint256 oraclePrice, uint256 fees, uint256 askMin, uint256 bidMax) = pool.getPoolInfo();

        assertEq(lastPrice, AK47_INITIAL_PRICE);
        assertEq(oraclePrice, AK47_INITIAL_PRICE);
        assertEq(fees, 0);
        assertEq(askMin, 0);
        assertEq(bidMax, 0);
    }

    function test_GetLastPrice() public {
        assertEq(pool.getLastPrice(), AK47_INITIAL_PRICE);
    }

    function test_UpdateOraclePrice_OnlyOwner() public {
        pool.updateOraclePrice(51000);
        (, uint256 oraclePrice, , , ) = pool.getPoolInfo();
        assertEq(oraclePrice, 51000);

        vm.prank(alice);
        vm.expectRevert();
        pool.updateOraclePrice(52000);
    }

    function test_SettlePnL_Profit() public {
        // Alice opens long at 50000
        PoolOrder memory openOrder = _createLongOrder(10, 50000, 1000e6);
        vm.prank(alice);
        OrderId orderId = pool.newOrder(openOrder);

        // Bob matches
        PoolOrder memory bobOrder = _createShortOrder(10, 50000, 1000e6);
        vm.prank(bob);
        pool.newOrder(bobOrder);

        // Price goes up, Alice closes at profit at 51000
        PoolOrder memory bobCloseOrder = _createShortOrder(10, 51000, 1000e6);
        vm.prank(bob);
        OrderId bobCloseId = pool.newOrder(bobCloseOrder);

        PoolOrder memory aliceCloseOrder = _createShortOrder(10, 51000, 0);
        vm.prank(alice);
        pool.closePosition(orderId, aliceCloseOrder);

        // Check Alice made profit
        // PnL = (51000 - 50000) * 10 / 100 * 10^6 = 100e6
        // After fees, Alice should have more than initial margin
        uint256 aliceBalanceAfter = vault.balanceOf(alice);
        // She started with 10000e6, deposited 1000e6, so should have ~9000e6 + profit
        assertGt(aliceBalanceAfter, 9000e6);
    }
}
