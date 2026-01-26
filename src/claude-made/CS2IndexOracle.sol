// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "./libraries/Ownable.sol";

/**
 * @title CS2IndexOracle
 * @notice Oracle for CS2 item prices
 */
contract CS2IndexOracle is Ownable {

    address public factory;
    address public priceFeeder;

    // Price data
    uint256 public priceX100;
    uint256 public lastUpdateTime;

    // Multiple price sources
    mapping(address => bool) public isPriceFeeder;
    mapping(address => uint256) public feederPrices;
    mapping(address => uint256) public feederTimestamps;

    uint256 public constant MAX_PRICE_AGE = 1800; // 30 minutes
    uint256 public constant MIN_FEEDERS = 1;

    event PriceUpdated(
        uint256 indexed newPrice,
        address indexed updater,
        uint256 timestamp
    );

    event PriceFeederAdded(address indexed feeder);
    event PriceFeederRemoved(address indexed feeder);

    constructor(uint256 _initialPrice) Ownable() {
        priceX100 = _initialPrice;
        lastUpdateTime = block.timestamp;
        factory = msg.sender;
    }

    /**
     * @notice Add a price feeder
     */
    function addPriceFeeder(address feeder) external onlyOwner {
        isPriceFeeder[feeder] = true;
        priceFeeder = feeder;
        emit PriceFeederAdded(feeder);
    }

    /**
     * @notice Remove a price feeder
     */
    function removePriceFeeder(address feeder) external onlyOwner {
        isPriceFeeder[feeder] = false;
        delete feederPrices[feeder];
        delete feederTimestamps[feeder];
        emit PriceFeederRemoved(feeder);
    }

    /**
     * @notice Update price (only price feeders)
     */
    function updatePrice(uint256 newPriceX100) external {
        require(isPriceFeeder[msg.sender] || msg.sender == owner(), "Not authorized");
        require(newPriceX100 > 0, "Invalid price");

        // Validate price change (max 50% in one update)
        if (priceX100 > 0) {
            uint256 maxPrice = (priceX100 * 150) / 100;
            uint256 minPrice = (priceX100 * 50) / 100;
            require(
                newPriceX100 <= maxPrice && newPriceX100 >= minPrice,
                "Price change too large"
            );
        }

        feederPrices[msg.sender] = newPriceX100;
        feederTimestamps[msg.sender] = block.timestamp;
        priceX100 = newPriceX100;
        lastUpdateTime = block.timestamp;

        emit PriceUpdated(newPriceX100, msg.sender, block.timestamp);
    }

    /**
     * @notice Get current price
     */
    function getPrice() external view returns (uint256) {
        require(block.timestamp - lastUpdateTime <= MAX_PRICE_AGE, "Price too old");
        require(priceX100 > 0, "Price not set");
        return priceX100;
    }

    /**
     * @notice Get latest price (doesn't revert if stale)
     */
    function latestPriceX100() external view returns (uint256) {
        return priceX100;
    }

    /**
     * @notice Get price with timestamp
     */
    function getPriceWithTimestamp() external view returns (uint256 price, uint256 timestamp) {
        require(priceX100 > 0, "Price not set");
        return (priceX100, lastUpdateTime);
    }

    /**
     * @notice Check if price is fresh
     */
    function isPriceFresh() external view returns (bool) {
        return (block.timestamp - lastUpdateTime <= MAX_PRICE_AGE) && (priceX100 > 0);
    }

    /**
     * @notice Emergency price update by owner
     */
    function emergencyUpdatePrice(uint256 newPriceX100) external onlyOwner {
        require(newPriceX100 > 0, "Invalid price");
        priceX100 = newPriceX100;
        lastUpdateTime = block.timestamp;
        emit PriceUpdated(newPriceX100, msg.sender, block.timestamp);
    }
}
