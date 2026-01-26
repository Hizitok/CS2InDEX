// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Vault.sol";
import "../src/Factory.sol";
import "../src/LiquidationEngine.sol";
import "../src/ADLEngine.sol";
import "../src/CS2IndexOracle.sol";
import "../src/Router.sol";

/**
 * @title DeployCS2InDEXMainnet
 * @notice Mainnet deployment script (uses real USDC, no mocks)
 * @dev Run with: forge script script/DeployMainnet.s.sol --rpc-url mainnet --broadcast --verify
 */
contract DeployCS2InDEXMainnet is Script {
    // Mainnet USDC address
    address public constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Deployment addresses
    Vault public vault;
    CS2InDEXFactory public factory;
    LiquidationEngine public liquidationEngine;
    ADLEngine public adlEngine;
    Router public router;

    // Configuration
    address public insuranceFund;
    address public priceFeeder;
    address public deployer;

    struct PoolConfig {
        string name;
        uint256 initialPriceX100;
        uint256 curDecimal;
    }

    PoolConfig[] public poolConfigs;

    function setUp() public {
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        insuranceFund = vm.envAddress("INSURANCE_FUND");
        priceFeeder = vm.envAddress("PRICE_FEEDER");

        // Configure pools with real market data
        poolConfigs.push(PoolConfig({
            name: "CS2-Global-Index",
            initialPriceX100: 400000000, // $4M (from Buff163)
            curDecimal: 6
        }));

        poolConfigs.push(PoolConfig({
            name: "CS2-Knives-Index",
            initialPriceX100: 70900000, // $709K (from Buff163)
            curDecimal: 6
        }));

        poolConfigs.push(PoolConfig({
            name: "CS2-Rifles-Index",
            initialPriceX100: 15000000, // $150K estimate
            curDecimal: 6
        }));

        poolConfigs.push(PoolConfig({
            name: "CS2-Gloves-Index",
            initialPriceX100: 25000000, // $250K estimate
            curDecimal: 6
        }));
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("========================================");
        console.log("Deploying CS2InDEX to MAINNET");
        console.log("========================================");
        console.log("USDC Address:", USDC_MAINNET);
        console.log("Deployer:", deployer);
        console.log("Insurance Fund:", insuranceFund);
        console.log("Price Feeder:", priceFeeder);
        console.log("");

        // Deploy core contracts
        vault = new Vault(USDC_MAINNET);
        console.log("Vault deployed:", address(vault));

        liquidationEngine = new LiquidationEngine(address(vault), insuranceFund);
        console.log("Liquidation Engine deployed:", address(liquidationEngine));

        adlEngine = new ADLEngine(address(vault));
        console.log("ADL Engine deployed:", address(adlEngine));

        factory = new CS2InDEXFactory(address(vault), insuranceFund);
        console.log("Factory deployed:", address(factory));

        router = new Router(address(vault), address(factory), USDC_MAINNET);
        console.log("Router deployed:", address(router));

        // Configure factory
        factory.setLiquidationEngine(address(liquidationEngine));
        factory.setADLEngine(address(adlEngine));
        factory.setPriceFeeder(priceFeeder, true);

        // Deploy pools
        for (uint256 i = 0; i < poolConfigs.length; i++) {
            PoolConfig memory config = poolConfigs[i];
            (address pool, address oracle, address nft) =
                factory.createPool(config.name, config.initialPriceX100, config.curDecimal);

            liquidationEngine.setPool(pool, true);
            adlEngine.setPool(pool, true);

            console.log("Pool deployed:", config.name);
            console.log("  Pool:", pool);
            console.log("  Oracle:", oracle);
            console.log("  NFT:", nft);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log("MAINNET Deployment Complete!");
        console.log("========================================");
        console.log("");
        console.log("CRITICAL: Verify all contracts immediately!");
        console.log("CRITICAL: Transfer ownership to multisig!");
        console.log("CRITICAL: Fund insurance fund with USDC!");
    }
}
