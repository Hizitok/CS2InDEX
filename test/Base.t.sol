// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {Pool} from "../src/Pool.sol";
import {positionNFT} from "../src/PositionNFT.sol";
import {CS2InDEXFactory} from "../src/Factory.sol";
import {CS2IndexOracle, LiquidationEngine, ADLEngine} from "../src/Engine.sol";
import {OrderTypes} from "../src/interfaces/OrderTypes.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/**
 * @title BaseTest
 * @notice Base test contract with common setup for all tests
 */
contract BaseTest is Test, OrderTypes {

    // Core contracts
    Vault public vault;
    CS2InDEXFactory public factory;
    LiquidationEngine public liquidationEngine;
    ADLEngine public adlEngine;
    MockERC20 public usdc;

    // Test users
    address public owner = address(this);
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public carol = address(0x3);
    address public insuranceFund = address(0x999);

    // Constants
    uint256 public constant INITIAL_BALANCE = 100_000e6; // 100k USDC
    uint256 public constant AK47_INITIAL_PRICE = 50000; // $500.00
    uint256 public constant AWP_INITIAL_PRICE = 1500000; // $15000.00

    function setUp() public virtual {
        // Deploy mock USDC (6 decimals)
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Mint USDC to test users
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
        usdc.mint(carol, INITIAL_BALANCE);

        // Deploy Vault
        vault = new Vault(address(usdc));

        // Deploy Factory
        factory = new CS2InDEXFactory(address(vault), insuranceFund);

        // Deploy Engines
        liquidationEngine = new LiquidationEngine(address(vault), insuranceFund);
        adlEngine = new ADLEngine(address(vault), address(liquidationEngine));

        // Initialize Factory with engines
        factory.initializeEngines(address(liquidationEngine), address(adlEngine));

        // Users approve vault
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(carol);
        usdc.approve(address(vault), type(uint256).max);
    }

    // Helper functions

    function _deployPool(string memory itemName, uint256 initialPrice)
        internal
        returns (address pool, address oracle, address nft)
    {
        (pool, oracle, nft) = factory.createPool(itemName, initialPrice, 6);
    }

    function _depositToVault(address user, uint256 amount) internal {
        vm.prank(user);
        vault.deposit(amount);
    }

    function _createLongOrder(uint256 size, uint256 price, uint256 margin)
        internal
        pure
        returns (PoolOrder memory)
    {
        return PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: size,
            priceX100: price,
            margin: margin
        });
    }

    function _createShortOrder(uint256 size, uint256 price, uint256 margin)
        internal
        pure
        returns (PoolOrder memory)
    {
        return PoolOrder({
            isSell: true,
            oType: orderType.Limit,
            size: size,
            priceX100: price,
            margin: margin
        });
    }

    function _createMarketOrder(bool isSell, uint256 size, uint256 margin)
        internal
        pure
        returns (PoolOrder memory)
    {
        return PoolOrder({
            isSell: isSell,
            oType: orderType.Market,
            size: size,
            priceX100: 0,
            margin: margin
        });
    }
}
