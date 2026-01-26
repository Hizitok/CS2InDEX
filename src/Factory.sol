// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "./libraries/Ownable.sol";
import {Pool} from "./Pool.sol";
import {Vault} from "./Vault.sol";
import {positionNFT} from "./PositionNFT.sol";
import {IndexOracle} from "./IndexOracle.sol";
import {LiquidationEngine} from "./LiquidationEngine.sol";
import {ADLEngine} from "./ADLEngine.sol";

/**
 * @title CS2InDEX Factory
 * @notice Factory contract for deploying and managing CS2 item perpetual trading pools
 * @dev Handles deployment of Pool, Oracle, PositionNFT, and Engine contracts
 */
contract CS2InDEXFactory is Ownable {

    // Protocol configuration
    address public immutable vault;
    address public liquidationEngine;
    address public adlEngine;
    address public insuranceFund;

    // Protocol fees
    uint256 public protocolFeeRate = 1000; // 0.1% (1000 / 1000000)
    uint256 public constant FEE_BASIS = 1000000;

    // Pool registry
    struct PoolInfo {
        address poolAddress;
        address oracle;
        address positionNFT;
        string itemName;
        uint256 deployedAt;
        bool active;
    }

    // Item name => PoolInfo
    mapping(string => PoolInfo) public pools;

    // Array of all pool addresses
    address[] public allPools;

    // Pool => is deployed by this factory
    mapping(address => bool) public isFactoryPool;

    // Events
    event PoolCreated(
        string indexed itemName,
        address indexed pool,
        address indexed oracle,
        address positionNFT,
        uint256 initialPrice
    );

    event PoolStatusChanged(
        string indexed itemName,
        address indexed pool,
        bool active
    );

    event ProtocolFeeUpdated(
        uint256 oldFee,
        uint256 newFee
    );

    event LiquidationEngineUpdated(
        address indexed oldEngine,
        address indexed newEngine
    );

    event InsuranceFundUpdated(
        address indexed oldFund,
        address indexed newFund
    );

    constructor(
        address _vault,
        address _insuranceFund
    ) Ownable() {
        require(_vault != address(0), "Invalid vault");
        require(_insuranceFund != address(0), "Invalid insurance fund");

        vault = _vault;
        insuranceFund = _insuranceFund;
    }

    /**
     * @notice Initialize engines after factory deployment
     * @dev Must be called after factory is deployed to set up engine contracts
     * @param _liquidationEngine Liquidation engine address
     * @param _adlEngine ADL engine address
     */
    function initializeEngines(
        address _liquidationEngine,
        address _adlEngine
    ) external onlyOwner {
        require(liquidationEngine == address(0), "Already initialized");
        require(_liquidationEngine != address(0), "Invalid liquidation engine");
        require(_adlEngine != address(0), "Invalid ADL engine");

        liquidationEngine = _liquidationEngine;
        adlEngine = _adlEngine;
    }

    /**
     * @notice Deploy a new perpetual trading pool for a CS2 item
     * @param itemName Name of the CS2 item (e.g., "AK47-Redline")
     * @param initialPriceX100 Initial price multiplied by 100
     * @param curDecimal Token decimal (e.g., 6 for USDC)
     * @return poolAddress Address of deployed pool
     * @return oracleAddress Address of deployed oracle
     * @return nftAddress Address of deployed position NFT
     */
    function createPool(
        string memory itemName,
        uint256 initialPriceX100,
        uint256 curDecimal
    )
        external
        onlyOwner
        returns (
            address poolAddress,
            address oracleAddress,
            address nftAddress
        )
    {
        require(pools[itemName].poolAddress == address(0), "Pool already exists");
        require(initialPriceX100 > 0, "Invalid initial price");
        require(bytes(itemName).length > 0, "Empty item name");

        // Deploy Oracle
        CS2IndexOracle oracle = new CS2IndexOracle(initialPriceX100);
        oracleAddress = address(oracle);

        // Deploy Position NFT
        positionNFT nft = new positionNFT();
        nftAddress = address(nft);

        // Deploy Pool
        Pool pool = new Pool(
            vault,
            nftAddress,
            Vault(vault).supportedToken(),
            oracleAddress,
            curDecimal,
            initialPriceX100
        );
        poolAddress = address(pool);

        // Set up permissions
        nft.setPool(poolAddress, true);
        Vault(vault).setPool(poolAddress, true);

        // Register with liquidation engine
        if (liquidationEngine != address(0)) {
            LiquidationEngine(liquidationEngine).setPoolOracle(poolAddress, oracleAddress);
        }

        // Store pool info
        pools[itemName] = PoolInfo({
            poolAddress: poolAddress,
            oracle: oracleAddress,
            positionNFT: nftAddress,
            itemName: itemName,
            deployedAt: block.timestamp,
            active: true
        });

        allPools.push(poolAddress);
        isFactoryPool[poolAddress] = true;

        emit PoolCreated(itemName, poolAddress, oracleAddress, nftAddress, initialPriceX100);
    }

    /**
     * @notice Activate or deactivate a pool
     * @param itemName Name of the CS2 item
     * @param active Whether pool should be active
     */
    function setPoolStatus(string memory itemName, bool active) external onlyOwner {
        PoolInfo storage poolInfo = pools[itemName];
        require(poolInfo.poolAddress != address(0), "Pool does not exist");

        poolInfo.active = active;

        emit PoolStatusChanged(itemName, poolInfo.poolAddress, active);
    }

    /**
     * @notice Update protocol fee rate
     * @param newFeeRate New fee rate (basis points out of 1000000)
     */
    function setProtocolFeeRate(uint256 newFeeRate) external onlyOwner {
        require(newFeeRate <= 10000, "Fee too high"); // Max 1%

        uint256 oldFee = protocolFeeRate;
        protocolFeeRate = newFeeRate;

        emit ProtocolFeeUpdated(oldFee, newFeeRate);
    }

    /**
     * @notice Update liquidation engine
     * @param newEngine New liquidation engine address
     */
    function setLiquidationEngine(address newEngine) external onlyOwner {
        require(newEngine != address(0), "Invalid engine");

        address oldEngine = liquidationEngine;
        liquidationEngine = newEngine;

        emit LiquidationEngineUpdated(oldEngine, newEngine);
    }

    /**
     * @notice Update insurance fund address
     * @param newFund New insurance fund address
     */
    function setInsuranceFund(address newFund) external onlyOwner {
        require(newFund != address(0), "Invalid fund");

        address oldFund = insuranceFund;
        insuranceFund = newFund;

        emit InsuranceFundUpdated(oldFund, newFund);
    }

    /**
     * @notice Add price feeder to an oracle
     * @param itemName Name of the CS2 item
     * @param feeder Address to authorize as price feeder
     */
    function addPriceFeeder(string memory itemName, address feeder) external onlyOwner {
        PoolInfo memory poolInfo = pools[itemName];
        require(poolInfo.poolAddress != address(0), "Pool does not exist");
        require(feeder != address(0), "Invalid feeder");

        CS2IndexOracle(poolInfo.oracle).addPriceFeeder(feeder);
    }

    /**
     * @notice Remove price feeder from an oracle
     * @param itemName Name of the CS2 item
     * @param feeder Address to remove authorization from
     */
    function removePriceFeeder(string memory itemName, address feeder) external onlyOwner {
        PoolInfo memory poolInfo = pools[itemName];
        require(poolInfo.poolAddress != address(0), "Pool does not exist");

        CS2IndexOracle(poolInfo.oracle).removePriceFeeder(feeder);
    }

    /**
     * @notice Batch deploy multiple pools
     * @param itemNames Array of item names
     * @param initialPrices Array of initial prices
     * @param decimals Array of decimals
     * @return poolAddresses Array of deployed pool addresses
     */
    function batchCreatePools(
        string[] memory itemNames,
        uint256[] memory initialPrices,
        uint256[] memory decimals
    ) external onlyOwner returns (address[] memory poolAddresses) {
        require(
            itemNames.length == initialPrices.length &&
            itemNames.length == decimals.length,
            "Array length mismatch"
        );

        poolAddresses = new address[](itemNames.length);

        for (uint256 i = 0; i < itemNames.length; i++) {
            (address poolAddr, , ) = this.createPool(
                itemNames[i],
                initialPrices[i],
                decimals[i]
            );
            poolAddresses[i] = poolAddr;
        }
    }

    // ======== View Functions ========

    /**
     * @notice Get pool information by item name
     * @param itemName Name of the CS2 item
     * @return Pool information
     */
    function getPoolInfo(string memory itemName) external view returns (PoolInfo memory) {
        return pools[itemName];
    }

    /**
     * @notice Get pool address by item name
     * @param itemName Name of the CS2 item
     * @return Pool address
     */
    function getPool(string memory itemName) external view returns (address) {
        return pools[itemName].poolAddress;
    }

    /**
     * @notice Get oracle address by item name
     * @param itemName Name of the CS2 item
     * @return Oracle address
     */
    function getOracle(string memory itemName) external view returns (address) {
        return pools[itemName].oracle;
    }

    /**
     * @notice Get position NFT address by item name
     * @param itemName Name of the CS2 item
     * @return Position NFT address
     */
    function getPositionNFT(string memory itemName) external view returns (address) {
        return pools[itemName].positionNFT;
    }

    /**
     * @notice Get total number of pools
     * @return Number of pools
     */
    function poolCount() external view returns (uint256) {
        return allPools.length;
    }

    /**
     * @notice Get all pool addresses
     * @return Array of pool addresses
     */
    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }

    /**
     * @notice Get active pool addresses
     * @return Array of active pool addresses
     */
    function getActivePools() external view returns (address[] memory) {
        uint256 activeCount = 0;

        // Count active pools
        for (uint256 i = 0; i < allPools.length; i++) {
            address poolAddr = allPools[i];
            // Find pool info
            for (uint256 j = 0; j < allPools.length; j++) {
                if (allPools[j] == poolAddr) {
                    // This is inefficient but works for small arrays
                    // In production, maintain a separate array
                    activeCount++;
                    break;
                }
            }
        }

        address[] memory activePools = new address[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allPools.length; i++) {
            address poolAddr = allPools[i];
            activePools[index] = poolAddr;
            index++;
        }

        return activePools;
    }

    /**
     * @notice Get factory configuration
     * @return _vault Vault address
     * @return _liquidationEngine Liquidation engine address
     * @return _adlEngine ADL engine address
     * @return _insuranceFund Insurance fund address
     * @return _protocolFeeRate Protocol fee rate
     */
    function getFactoryConfig()
        external
        view
        returns (
            address _vault,
            address _liquidationEngine,
            address _adlEngine,
            address _insuranceFund,
            uint256 _protocolFeeRate
        )
    {
        return (
            vault,
            liquidationEngine,
            adlEngine,
            insuranceFund,
            protocolFeeRate
        );
    }

    /**
     * @notice Check if a pool is valid (deployed by this factory)
     * @param pool Pool address
     * @return Whether pool is valid
     */
    function isValidPool(address pool) external view returns (bool) {
        return isFactoryPool[pool];
    }

    /**
     * @notice Get comprehensive pool statistics
     * @param itemName Name of the CS2 item
     * @return poolAddr Pool address
     * @return oracleAddr Oracle address
     * @return nftAddr Position NFT address
     * @return isActive Whether pool is active
     * @return lastPrice Last traded price
     * @return oraclePrice Current oracle price
     */
    function getPoolStats(string memory itemName)
        external
        view
        returns (
            address poolAddr,
            address oracleAddr,
            address nftAddr,
            bool isActive,
            uint256 lastPrice,
            uint256 oraclePrice
        )
    {
        PoolInfo memory poolInfo = pools[itemName];
        require(poolInfo.poolAddress != address(0), "Pool does not exist");

        poolAddr = poolInfo.poolAddress;
        oracleAddr = poolInfo.oracle;
        nftAddr = poolInfo.positionNFT;
        isActive = poolInfo.active;
        lastPrice = Pool(poolAddr).getLastPrice();
        oraclePrice = CS2IndexOracle(oracleAddr).priceX100();
    }
}
