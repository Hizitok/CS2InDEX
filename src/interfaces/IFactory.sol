// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFactory
 * @notice Interface for the CS2InDEX Factory contract
 * @dev Factory deploys and manages trading pools for different CS2 indices
 */
interface IFactory {
    /**
     * @notice Pool information struct
     */
    struct PoolInfo {
        address poolAddress;
        address oracle;
        address positionNFT;
        string itemName;
        uint256 createdAt;
        bool isActive;
    }

    /**
     * @notice Create a new trading pool for a CS2 index
     * @param itemName Name of the CS2 index (e.g., "CS2-Global-Index")
     * @param initialPriceX100 Initial price multiplied by 100
     * @param curDecimal Decimal places for currency (6 for USDC)
     * @return poolAddress Address of deployed pool
     * @return oracleAddress Address of deployed oracle
     * @return nftAddress Address of deployed position NFT
     */
    function createPool(
        string memory itemName,
        uint256 initialPriceX100,
        uint256 curDecimal
    ) external returns (address poolAddress, address oracleAddress, address nftAddress);

    /**
     * @notice Batch create multiple pools
     * @param itemNames Array of item names
     * @param initialPrices Array of initial prices
     * @param decimals Array of decimal places
     * @return pools Array of deployed pool addresses
     */
    function batchCreatePools(
        string[] memory itemNames,
        uint256[] memory initialPrices,
        uint256[] memory decimals
    ) external returns (address[] memory pools);

    /**
     * @notice Toggle pool active status
     * @param itemName Item name
     * @param active New active status
     */
    function setPoolStatus(string memory itemName, bool active) external;

    /**
     * @notice Update protocol fee rate
     * @param newFeeRate New fee rate in basis points (e.g., 30 = 0.3%)
     */
    function setProtocolFeeRate(uint256 newFeeRate) external;

    /**
     * @notice Set liquidation engine address
     * @param newEngine New liquidation engine address
     */
    function setLiquidationEngine(address newEngine) external;

    /**
     * @notice Set insurance fund address
     * @param newFund New insurance fund address
     */
    function setInsuranceFund(address newFund) external;

    /**
     * @notice Add authorized price feeder for a pool
     * @param itemName Item name
     * @param feeder Price feeder address
     */
    function addPriceFeeder(string memory itemName, address feeder) external;

    /**
     * @notice Remove price feeder
     * @param itemName Item name
     * @param feeder Price feeder address to remove
     */
    function removePriceFeeder(string memory itemName, address feeder) external;

    /**
     * @notice Get pool information by item name
     * @param itemName Item name
     * @return Pool information struct
     */
    function getPoolInfo(string memory itemName) external view returns (PoolInfo memory);

    /**
     * @notice Get pool address by item name
     * @param itemName Item name
     * @return Pool address
     */
    function getPool(string memory itemName) external view returns (address);

    /**
     * @notice Get oracle address by item name
     * @param itemName Item name
     * @return Oracle address
     */
    function getOracle(string memory itemName) external view returns (address);

    /**
     * @notice Get position NFT address by item name
     * @param itemName Item name
     * @return Position NFT address
     */
    function getPositionNFT(string memory itemName) external view returns (address);

    /**
     * @notice Get total number of pools
     * @return Total pool count
     */
    function poolCount() external view returns (uint256);

    /**
     * @notice Get all pool addresses
     * @return Array of all pool addresses
     */
    function getAllPools() external view returns (address[] memory);

    /**
     * @notice Get all active pool addresses
     * @return Array of active pool addresses
     */
    function getActivePools() external view returns (address[] memory);

    /**
     * @notice Check if an address is a valid factory-deployed pool
     * @param pool Address to check
     * @return True if valid pool
     */
    function isValidPool(address pool) external view returns (bool);

    /**
     * @notice Get vault address
     * @return Vault address
     */
    function vault() external view returns (address);

    /**
     * @notice Get liquidation engine address
     * @return Liquidation engine address
     */
    function liquidationEngine() external view returns (address);

    /**
     * @notice Get insurance fund address
     * @return Insurance fund address
     */
    function insuranceFund() external view returns (address);

    // Events
    event PoolCreated(
        string indexed itemName,
        address indexed poolAddress,
        address oracle,
        address positionNFT,
        uint256 initialPrice
    );
    event PoolStatusChanged(string indexed itemName, bool isActive);
    event LiquidationEngineUpdated(address indexed oldEngine, address indexed newEngine);
    event InsuranceFundUpdated(address indexed oldFund, address indexed newFund);
    event PriceFeederAdded(string indexed itemName, address indexed feeder);
    event PriceFeederRemoved(string indexed itemName, address indexed feeder);
}
