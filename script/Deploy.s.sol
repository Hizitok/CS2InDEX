// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Vault.sol";
import "../src/Factory.sol";
import "../src/Pool.sol";
import "../src/PositionNFT.sol";
import "../src/LiquidationEngine.sol";
import "../src/ADLEngine.sol";
import "../src/CS2IndexOracle.sol";
import "../src/Router.sol";
import "../test/mocks/MockERC20.sol";

/**
 * @title DeployCS2InDEX
 * @notice Deployment script for the complete CS2InDEX protocol
 * @dev Run with: forge script script/Deploy.s.sol --rpc-url <network> --broadcast
 */
contract DeployCS2InDEX is Script {
    // Deployment addresses (will be set during deployment)
    MockERC20 public usdc;
    Vault public vault;
    CS2InDEXFactory public factory;
    LiquidationEngine public liquidationEngine;
    ADLEngine public adlEngine;
    Router public router;

    // Insurance fund address (configure this)
    address public insuranceFund;

    // Price feeder address (configure this)
    address public priceFeeder;

    // Deployer
    address public deployer;

    // Pool information for different CS2 indices
    struct PoolConfig {
        string name;
        uint256 initialPriceX100; // Price * 100 (e.g., $500 = 50000)
        uint256 curDecimal; // 6 for USDC
    }

    PoolConfig[] public poolConfigs;

    function setUp() public {
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        insuranceFund = vm.envOr("INSURANCE_FUND", deployer);
        priceFeeder = vm.envOr("PRICE_FEEDER", deployer);

        // Configure pools for different CS2 indices
        // Prices are from real-world data (skinflow.gg / esportfire.com)
        poolConfigs.push(PoolConfig({
            name: "CS2-Global-Index",
            initialPriceX100: 400000000, // ~$4,000,000 per index unit
            curDecimal: 6
        }));

        poolConfigs.push(PoolConfig({
            name: "CS2-Knives-Index",
            initialPriceX100: 70900000, // ~$709,000 per index unit
            curDecimal: 6
        }));

        poolConfigs.push(PoolConfig({
            name: "AK47-Redline",
            initialPriceX100: 5000, // $50.00
            curDecimal: 6
        }));

        poolConfigs.push(PoolConfig({
            name: "AWP-Dragon-Lore",
            initialPriceX100: 250000, // $2,500.00
            curDecimal: 6
        }));

        poolConfigs.push(PoolConfig({
            name: "M4A4-Howl",
            initialPriceX100: 400000, // $4,000.00
            curDecimal: 6
        }));

        poolConfigs.push(PoolConfig({
            name: "Karambit-Fade",
            initialPriceX100: 180000, // $1,800.00
            curDecimal: 6
        }));
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("========================================");
        console.log("Deploying CS2InDEX Protocol");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Insurance Fund:", insuranceFund);
        console.log("Price Feeder:", priceFeeder);
        console.log("");

        // Step 1: Deploy USDC (MockERC20 for testnet, use real USDC on mainnet)
        console.log("Step 1: Deploying USDC...");
        usdc = new MockERC20("USD Coin", "USDC", 6);
        console.log("USDC deployed at:", address(usdc));
        console.log("");

        // Step 2: Deploy Vault
        console.log("Step 2: Deploying Vault...");
        vault = new Vault(address(usdc));
        console.log("Vault deployed at:", address(vault));
        console.log("");

        // Step 3: Deploy Liquidation Engine
        console.log("Step 3: Deploying Liquidation Engine...");
        liquidationEngine = new LiquidationEngine(address(vault), insuranceFund);
        console.log("Liquidation Engine deployed at:", address(liquidationEngine));
        console.log("");

        // Step 4: Deploy ADL Engine
        console.log("Step 4: Deploying ADL Engine...");
        adlEngine = new ADLEngine(address(vault));
        console.log("ADL Engine deployed at:", address(adlEngine));
        console.log("");

        // Step 5: Deploy Factory
        console.log("Step 5: Deploying Factory...");
        factory = new CS2InDEXFactory(
            address(vault),
            insuranceFund
        );
        console.log("Factory deployed at:", address(factory));
        console.log("");

        // Step 6: Configure Factory with Engines
        console.log("Step 6: Configuring Factory...");
        factory.setLiquidationEngine(address(liquidationEngine));
        factory.setADLEngine(address(adlEngine));
        factory.setPriceFeeder(priceFeeder, true);
        console.log("Factory configured successfully");
        console.log("");

        // Step 6.5: Deploy Router
        console.log("Step 6.5: Deploying Router...");
        router = new Router(address(vault), address(factory), address(usdc));
        console.log("Router deployed at:", address(router));
        console.log("");

        // Step 7: Deploy Pools for each CS2 Index
        console.log("Step 7: Deploying Pools for CS2 Indices...");
        console.log("Total pools to deploy:", poolConfigs.length);
        console.log("");

        for (uint256 i = 0; i < poolConfigs.length; i++) {
            PoolConfig memory config = poolConfigs[i];

            console.log("Deploying pool", i + 1, "of", poolConfigs.length);
            console.log("  Name:", config.name);
            console.log("  Initial Price:", config.initialPriceX100);

            (address poolAddress, address oracleAddress, address nftAddress) =
                factory.createPool(config.name, config.initialPriceX100, config.curDecimal);

            console.log("  Pool:", poolAddress);
            console.log("  Oracle:", oracleAddress);
            console.log("  NFT:", nftAddress);
            console.log("");

            // Configure engines for this pool
            liquidationEngine.setPool(poolAddress, true);
            adlEngine.setPool(poolAddress, true);
        }

        vm.stopBroadcast();

        // Print deployment summary
        printDeploymentSummary();
    }

    function printDeploymentSummary() internal view {
        console.log("========================================");
        console.log("Deployment Summary");
        console.log("========================================");
        console.log("");
        console.log("Core Contracts:");
        console.log("  USDC:                ", address(usdc));
        console.log("  Vault:               ", address(vault));
        console.log("  Factory:             ", address(factory));
        console.log("  Router:              ", address(router));
        console.log("  Liquidation Engine:  ", address(liquidationEngine));
        console.log("  ADL Engine:          ", address(adlEngine));
        console.log("");
        console.log("Pools Deployed:", poolConfigs.length);
        console.log("");

        // Get pool information from factory
        for (uint256 i = 0; i < poolConfigs.length; i++) {
            CS2InDEXFactory.PoolInfo memory info = factory.getPoolInfo(poolConfigs[i].name);
            console.log("Pool", i + 1, ":", poolConfigs[i].name);
            console.log("  Pool Address:   ", info.pool);
            console.log("  Oracle Address: ", info.oracle);
            console.log("  NFT Address:    ", info.positionNFT);
            console.log("  Active:         ", info.isActive);
            console.log("");
        }

        console.log("========================================");
        console.log("Deployment Complete!");
        console.log("========================================");
        console.log("");
        console.log("Next Steps:");
        console.log("1. Verify contracts on Etherscan:");
        console.log("   forge verify-contract <address> <contract> --chain <chain-id>");
        console.log("");
        console.log("2. Update frontend configuration:");
        console.log("   - Copy contract addresses to frontend/src/config/contracts.ts");
        console.log("   - Update NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID in .env.local");
        console.log("");
        console.log("3. Start price feed service:");
        console.log("   - Configure oracle updater with price feeder key");
        console.log("   - Set up automated price updates from skinflow.gg/esportfire.com");
        console.log("");
        console.log("4. Fund insurance fund:");
        console.log("   - Transfer USDC to insurance fund address");
        console.log("   - Recommended: 10% of expected TVL");
        console.log("");
    }
}
