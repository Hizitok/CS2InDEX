// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Base.t.sol";
import {IPosition} from "../src/interfaces/IPosition.sol";

contract EngineTest is BaseTest {

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

        // Set oracle for liquidation engine
        liquidationEngine.setPoolOracle(address(pool), address(oracle));

        // Add owner as price feeder
        oracle.addPriceFeeder(owner);

        // Deposit to vault
        _depositToVault(alice, 10_000e6);
        _depositToVault(bob, 10_000e6);
        _depositToVault(carol, 10_000e6);
    }

    function test_Oracle_UpdatePrice() public {
        uint256 newPrice = 51000;

        oracle.updatePrice(newPrice);

        assertEq(oracle.priceX100(), newPrice);
    }

    function test_Oracle_UpdatePrice_RevertUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert("Not authorized");
        oracle.updatePrice(51000);
    }

    function test_Oracle_UpdatePrice_RevertPriceTooLarge() public {
        // Try to update by more than 50%
        vm.expectRevert("Price change too large");
        oracle.updatePrice(AK47_INITIAL_PRICE * 2);
    }

    function test_Oracle_GetPrice() public {
        uint256 price = oracle.getPrice();
        assertEq(price, AK47_INITIAL_PRICE);
    }

    function test_Oracle_GetPriceWithTimestamp() public {
        (uint256 price, uint256 timestamp) = oracle.getPriceWithTimestamp();
        assertEq(price, AK47_INITIAL_PRICE);
        assertEq(timestamp, block.timestamp);
    }

    function test_Oracle_IsPriceFresh() public {
        assertTrue(oracle.isPriceFresh());

        // Warp time forward by 2 hours
        vm.warp(block.timestamp + 2 hours);

        assertFalse(oracle.isPriceFresh());
    }

    function test_Oracle_AddRemovePriceFeeder() public {
        address newFeeder = address(0x456);

        oracle.addPriceFeeder(newFeeder);
        assertTrue(oracle.isPriceFeeder(newFeeder));

        oracle.removePriceFeeder(newFeeder);
        assertFalse(oracle.isPriceFeeder(newFeeder));
    }

    function test_Liquidation_CheckLiquidatable() public {
        // Alice opens 5x leveraged long position
        PoolOrder memory openOrder = _createLongOrder(100, 50000, 1000e6);
        vm.prank(alice);
        OrderId orderId = pool.newOrder(openOrder);

        // Bob matches
        PoolOrder memory bobOrder = _createShortOrder(100, 50000, 5000e6);
        vm.prank(bob);
        pool.newOrder(bobOrder);

        // Initially not liquidatable
        (bool liquidatable, uint256 marginRatio) = liquidationEngine.checkLiquidatable(address(pool), orderId);
        assertFalse(liquidatable);
        assertGt(marginRatio, 500); // Above 5% maintenance margin

        // Price drops by 15%
        oracle.updatePrice(42500); // 50000 * 0.85

        // Now should be liquidatable
        (liquidatable, marginRatio) = liquidationEngine.checkLiquidatable(address(pool), orderId);
        assertTrue(liquidatable);
        assertLt(marginRatio, 500);
    }

    function test_Liquidation_Execute() public {
        // Deposit to insurance fund
        vm.startPrank(owner);
        usdc.mint(owner, 10_000e6);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(10_000e6);
        liquidationEngine.depositInsuranceFund(5_000e6);
        vm.stopPrank();

        // Alice opens high leverage position
        PoolOrder memory openOrder = _createLongOrder(100, 50000, 1000e6);
        vm.prank(alice);
        OrderId orderId = pool.newOrder(openOrder);

        // Bob matches
        PoolOrder memory bobOrder = _createShortOrder(100, 50000, 5000e6);
        vm.prank(bob);
        pool.newOrder(bobOrder);

        // Price drops significantly
        oracle.updatePrice(42500);

        // Carol liquidates Alice's position
        vm.prank(carol);
        liquidationEngine.liquidate(address(pool), orderId);

        // Position should be force closed
        Position memory pos = IPosition(address(nft)).getPosition(orderId);
        assertTrue(pos.status == posStatus.forceClose);
        assertTrue(liquidationEngine.isLiquidated(orderId));
    }

    function test_Liquidation_RevertNotLiquidatable() public {
        // Alice opens healthy position
        PoolOrder memory openOrder = _createLongOrder(10, 50000, 2000e6);
        vm.prank(alice);
        OrderId orderId = pool.newOrder(openOrder);

        // Bob matches
        PoolOrder memory bobOrder = _createShortOrder(10, 50000, 1000e6);
        vm.prank(bob);
        pool.newOrder(bobOrder);

        // Try to liquidate healthy position
        vm.prank(carol);
        vm.expectRevert("Position not liquidatable");
        liquidationEngine.liquidate(address(pool), orderId);
    }

    function test_Liquidation_InsuranceFundDeposit() public {
        vm.startPrank(owner);
        usdc.mint(owner, 5_000e6);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(5_000e6);

        liquidationEngine.depositInsuranceFund(1_000e6);
        vm.stopPrank();

        assertEq(liquidationEngine.insuranceFundBalance(), 1_000e6);
    }

    function test_Liquidation_InsuranceFundWithdraw() public {
        // Deposit first
        vm.startPrank(owner);
        usdc.mint(owner, 5_000e6);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(5_000e6);
        liquidationEngine.depositInsuranceFund(1_000e6);

        // Withdraw
        liquidationEngine.withdrawInsuranceFund(500e6);
        vm.stopPrank();

        assertEq(liquidationEngine.insuranceFundBalance(), 500e6);
    }

    function test_Liquidation_GetPositionHealth() public {
        // Alice opens position
        PoolOrder memory openOrder = _createLongOrder(10, 50000, 1000e6);
        vm.prank(alice);
        OrderId orderId = pool.newOrder(openOrder);

        // Bob matches
        PoolOrder memory bobOrder = _createShortOrder(10, 50000, 1000e6);
        vm.prank(bob);
        pool.newOrder(bobOrder);

        (uint256 marginRatio, bool isHealthy) = liquidationEngine.getPositionHealth(address(pool), orderId);

        assertGt(marginRatio, 500);
        assertTrue(isHealthy);
    }

    function test_ADL_CalculateScore() public {
        // Alice opens profitable position
        PoolOrder memory openOrder = _createLongOrder(10, 50000, 1000e6);
        vm.prank(alice);
        OrderId orderId = pool.newOrder(openOrder);

        // Bob matches
        PoolOrder memory bobOrder = _createShortOrder(10, 50000, 1000e6);
        vm.prank(bob);
        pool.newOrder(bobOrder);

        // Price increases
        oracle.updatePrice(55000);

        // Calculate ADL score (should be positive since profitable)
        int256 score = adlEngine.calculateADLScore(address(pool), orderId);
        assertGt(score, 0);
    }

    function test_ADL_AddToQueue() public {
        // Alice opens position
        PoolOrder memory openOrder = _createLongOrder(10, 50000, 1000e6);
        vm.prank(alice);
        OrderId orderId = pool.newOrder(openOrder);

        // Bob matches
        PoolOrder memory bobOrder = _createShortOrder(10, 50000, 1000e6);
        vm.prank(bob);
        pool.newOrder(bobOrder);

        // Price increases (position becomes profitable)
        oracle.updatePrice(55000);

        // Add to ADL queue
        adlEngine.addToADLQueue(address(pool), orderId);

        assertEq(adlEngine.getADLQueueLength(address(pool)), 1);
    }

    function test_Liquidation_SetPoolOracle() public {
        address newOracle = address(0x789);

        liquidationEngine.setPoolOracle(address(pool), newOracle);

        assertEq(liquidationEngine.poolOracles(address(pool)), newOracle);
    }

    function test_Oracle_EmergencyUpdatePrice() public {
        // Emergency update bypasses price change validation
        oracle.emergencyUpdatePrice(100000); // 2x increase

        assertEq(oracle.priceX100(), 100000);
    }
}
