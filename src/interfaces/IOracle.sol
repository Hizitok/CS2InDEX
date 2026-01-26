// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IOracle
 * @notice Interface for CS2 Index Oracle
 * @dev Provides price feeds for CS2 indices from external sources
 */
interface IOracle {
    /**
     * @notice Maximum age for price data (30 minutes)
     */
    function MAX_PRICE_AGE() external view returns (uint256);

    /**
     * @notice Add authorized price feeder
     * @param feeder Price feeder address
     */
    function addPriceFeeder(address feeder) external;

    /**
     * @notice Remove price feeder
     * @param feeder Price feeder address to remove
     */
    function removePriceFeeder(address feeder) external;

    /**
     * @notice Update oracle price
     * @param newPriceX100 New price multiplied by 100
     * @dev Only callable by authorized price feeders or owner
     */
    function updatePrice(uint256 newPriceX100) external;

    /**
     * @notice Get current price (reverts if stale)
     * @return Current price multiplied by 100
     */
    function getPrice() external view returns (uint256);

    /**
     * @notice Get price with timestamp
     * @return price Current price multiplied by 100
     * @return timestamp Last update timestamp
     */
    function getPriceWithTimestamp() external view returns (uint256 price, uint256 timestamp);

    /**
     * @notice Check if price is fresh (within MAX_PRICE_AGE)
     * @return True if price is fresh
     */
    function isPriceFresh() external view returns (bool);

    /**
     * @notice Emergency price update (owner only)
     * @param newPriceX100 New price to set
     * @dev Bypasses feeder authorization in emergencies
     */
    function emergencyUpdatePrice(uint256 newPriceX100) external;

    /**
     * @notice Get latest price (view function, doesn't revert)
     * @return Latest price multiplied by 100
     */
    function latestPriceX100() external view returns (uint256);

    /**
     * @notice Get last update timestamp
     * @return Last update timestamp
     */
    function lastUpdateTime() external view returns (uint256);

    /**
     * @notice Get price feeder address (legacy single-feeder support)
     * @return Price feeder address
     */
    function priceFeeder() external view returns (address);

    /**
     * @notice Check if address is authorized price feeder
     * @param feeder Address to check
     * @return True if authorized
     */
    function isPriceFeeder(address feeder) external view returns (bool);

    /**
     * @notice Get price submitted by specific feeder
     * @param feeder Feeder address
     * @return price Price submitted by feeder
     * @return timestamp When feeder submitted price
     */
    function feederPrices(address feeder) external view returns (uint256 price, uint256 timestamp);

    // Events
    event PriceUpdated(
        address indexed feeder,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 timestamp
    );
    event PriceFeederAdded(address indexed feeder);
    event PriceFeederRemoved(address indexed feeder);
    event EmergencyPriceUpdate(address indexed updater, uint256 newPrice);
    event PriceStale(uint256 lastUpdate, uint256 currentTime, uint256 maxAge);
}
