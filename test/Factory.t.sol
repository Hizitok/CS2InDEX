// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Base.t.sol";

contract FactoryTest is BaseTest {

    function test_CreatePool() public {
        (address poolAddr, address oracleAddr, address nftAddr) = factory.createPool(
            "M4A4-Howl",
            300000,
            6
        );

        // Check addresses are not zero
        assertTrue(poolAddr != address(0));
        assertTrue(oracleAddr != address(0));
        assertTrue(nftAddr != address(0));

        // Check pool registered
        assertTrue(factory.isValidPool(poolAddr));

        // Check pool info
        CS2InDEXFactory.PoolInfo memory info = factory.getPoolInfo("M4A4-Howl");
        assertEq(info.poolAddress, poolAddr);
        assertEq(info.oracle, oracleAddr);
        assertEq(info.positionNFT, nftAddr);
        assertEq(info.itemName, "M4A4-Howl");
        assertTrue(info.active);
    }

    function test_CreatePool_RevertDuplicate() public {
        factory.createPool("AK47-Redline", 50000, 6);

        vm.expectRevert("Pool already exists");
        factory.createPool("AK47-Redline", 50000, 6);
    }

    function test_CreatePool_RevertInvalidPrice() public {
        vm.expectRevert("Invalid initial price");
        factory.createPool("AK47-Redline", 0, 6);
    }

    function test_CreatePool_RevertEmptyName() public {
        vm.expectRevert("Empty item name");
        factory.createPool("", 50000, 6);
    }

    function test_BatchCreatePools() public {
        string[] memory names = new string[](3);
        names[0] = "AK47-Redline";
        names[1] = "AWP-Dragon Lore";
        names[2] = "M4A4-Howl";

        uint256[] memory prices = new uint256[](3);
        prices[0] = 50000;
        prices[1] = 1500000;
        prices[2] = 300000;

        uint256[] memory decimals = new uint256[](3);
        decimals[0] = 6;
        decimals[1] = 6;
        decimals[2] = 6;

        address[] memory pools = factory.batchCreatePools(names, prices, decimals);

        assertEq(pools.length, 3);
        assertEq(factory.poolCount(), 3);
    }

    function test_BatchCreatePools_RevertLengthMismatch() public {
        string[] memory names = new string[](2);
        names[0] = "AK47";
        names[1] = "AWP";

        uint256[] memory prices = new uint256[](3);
        prices[0] = 50000;
        prices[1] = 150000;
        prices[2] = 300000;

        uint256[] memory decimals = new uint256[](2);
        decimals[0] = 6;
        decimals[1] = 6;

        vm.expectRevert("Array length mismatch");
        factory.batchCreatePools(names, prices, decimals);
    }

    function test_SetPoolStatus() public {
        factory.createPool("AK47-Redline", 50000, 6);

        factory.setPoolStatus("AK47-Redline", false);

        CS2InDEXFactory.PoolInfo memory info = factory.getPoolInfo("AK47-Redline");
        assertFalse(info.active);
    }

    function test_SetPoolStatus_RevertNonexistent() public {
        vm.expectRevert("Pool does not exist");
        factory.setPoolStatus("Nonexistent", false);
    }

    function test_SetProtocolFeeRate() public {
        uint256 newFee = 2000; // 0.2%

        factory.setProtocolFeeRate(newFee);

        (, , , , uint256 feeRate) = factory.getFactoryConfig();
        assertEq(feeRate, newFee);
    }

    function test_SetProtocolFeeRate_RevertTooHigh() public {
        vm.expectRevert("Fee too high");
        factory.setProtocolFeeRate(20000); // 2%
    }

    function test_AddPriceFeeder() public {
        factory.createPool("AK47-Redline", 50000, 6);

        address feeder = address(0x456);
        factory.addPriceFeeder("AK47-Redline", feeder);

        address oracleAddr = factory.getOracle("AK47-Redline");
        CS2IndexOracle oracle = CS2IndexOracle(oracleAddr);

        assertTrue(oracle.isPriceFeeder(feeder));
    }

    function test_RemovePriceFeeder() public {
        factory.createPool("AK47-Redline", 50000, 6);

        address feeder = address(0x456);
        factory.addPriceFeeder("AK47-Redline", feeder);
        factory.removePriceFeeder("AK47-Redline", feeder);

        address oracleAddr = factory.getOracle("AK47-Redline");
        CS2IndexOracle oracle = CS2IndexOracle(oracleAddr);

        assertFalse(oracle.isPriceFeeder(feeder));
    }

    function test_GetPool() public {
        (address poolAddr, , ) = factory.createPool("AK47-Redline", 50000, 6);

        assertEq(factory.getPool("AK47-Redline"), poolAddr);
    }

    function test_GetOracle() public {
        (, address oracleAddr, ) = factory.createPool("AK47-Redline", 50000, 6);

        assertEq(factory.getOracle("AK47-Redline"), oracleAddr);
    }

    function test_GetPositionNFT() public {
        (, , address nftAddr) = factory.createPool("AK47-Redline", 50000, 6);

        assertEq(factory.getPositionNFT("AK47-Redline"), nftAddr);
    }

    function test_PoolCount() public {
        assertEq(factory.poolCount(), 0);

        factory.createPool("AK47-Redline", 50000, 6);
        assertEq(factory.poolCount(), 1);

        factory.createPool("AWP-Dragon Lore", 1500000, 6);
        assertEq(factory.poolCount(), 2);
    }

    function test_GetAllPools() public {
        factory.createPool("AK47-Redline", 50000, 6);
        factory.createPool("AWP-Dragon Lore", 1500000, 6);

        address[] memory pools = factory.getAllPools();

        assertEq(pools.length, 2);
    }

    function test_GetPoolStats() public {
        factory.createPool("AK47-Redline", 50000, 6);

        (
            address poolAddr,
            address oracleAddr,
            address nftAddr,
            bool isActive,
            uint256 lastPrice,
            uint256 oraclePrice
        ) = factory.getPoolStats("AK47-Redline");

        assertTrue(poolAddr != address(0));
        assertTrue(oracleAddr != address(0));
        assertTrue(nftAddr != address(0));
        assertTrue(isActive);
        assertEq(lastPrice, 50000);
        assertEq(oraclePrice, 50000);
    }

    function test_GetFactoryConfig() public {
        (
            address _vault,
            address _liquidationEngine,
            address _adlEngine,
            address _insuranceFund,
            uint256 _protocolFeeRate
        ) = factory.getFactoryConfig();

        assertEq(_vault, address(vault));
        assertEq(_liquidationEngine, address(liquidationEngine));
        assertEq(_adlEngine, address(adlEngine));
        assertEq(_insuranceFund, insuranceFund);
        assertEq(_protocolFeeRate, 1000);
    }

    function test_IsValidPool() public {
        (address poolAddr, , ) = factory.createPool("AK47-Redline", 50000, 6);

        assertTrue(factory.isValidPool(poolAddr));
        assertFalse(factory.isValidPool(address(0x123)));
    }

    function test_SetLiquidationEngine() public {
        address newEngine = address(0x789);

        factory.setLiquidationEngine(newEngine);

        (, address liquidationEngineAddr, , , ) = factory.getFactoryConfig();
        assertEq(liquidationEngineAddr, newEngine);
    }

    function test_SetInsuranceFund() public {
        address newFund = address(0x888);

        factory.setInsuranceFund(newFund);

        (, , , address fundAddr, ) = factory.getFactoryConfig();
        assertEq(fundAddr, newFund);
    }

    function test_InitializeEngines_RevertAlreadyInitialized() public {
        vm.expectRevert("Already initialized");
        factory.initializeEngines(address(liquidationEngine), address(adlEngine));
    }
}
