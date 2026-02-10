// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "./libraries/Ownable.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IOracle} from "./interfaces/IOracle.sol";

/**
 * @title IndexOracle and Funding rate contract
 * @notice Oracle for CS2 item prices
 */
contract IndexOracle is Ownable, IOracle {

    address public factory;

    uint256 public settlementPeriod = 8 hours;
    uint256 public lastFundingTime;

    // Funding rate parameters (in basis points, 1 bp = 0.01%)
    int128 public constant BASIS_POINT = 10000;      // 100% = 10000 bp
    int128 public constant BASE_RATE = 3;            // 0.03% = 3 bp (daily base rate)
    int128 public constant CLAMP_RANGE = 5;          // 0.05% = 5 bp
    int128 public constant DEPTH_WEIGHTED_AMOUNT_BASE = 200; // 200 USDT per max leverage

    // Funding rate limits (configurable)
    int128 public fundingRateCap = 200;    // 2% = 200 bp
    int128 public fundingRateFloor = -200; // -2% = -200 bp

    /**
     * Premium Index Calculation Formula:
     *
     * Premium Index = [max(0, Depth Weighted Bid - Index Price) - max(0, Index Price - Depth Weighted Ask)] / Index Price
     *
     * Average Premium Index uses weighted average algorithm from past settlement period:
     * Avg Premium Index = (1×P1 + 2×P2 + ... + n×Pn) / (1+2+...+n)
     *
     * Funding Rate = clamp[Avg Premium Index + clamp(Interest Rate - Avg Premium Index, 0.05%, -0.05%), Cap, Floor]
     *
     * Interest Rate = 0.03% / (24 hours / Settlement Period)
    */

    struct PoolFundingData {
        // EVM Slot 0
        uint64 lastFundingTime;    // Last Funding time of this pool
        uint64 sampleCount;        // Number of samples in current period
        uint128 cumWeight;          // Cumulative weight sum
        // EVM Slot 1
        uint128 cumWeightedPremium;  // Cumulative weighted premium index
        uint128 cumWeightedOracle; // cumulative weighted oracle price
    }

    mapping(address => bool) private authorizedPools;
    mapping(address => uint256) public oraclePrice;           // Index price for each pool
    mapping(address => uint256) public updateTime;
    mapping(address => PoolFundingData) private poolData;     // Premium accumulator

    error UnauthorizedPool();

    constructor() Ownable(msg.sender) {
        factory = msg.sender;
        lastFundingTime = block.timestamp;
    }

    modifier onlyPool(address pool) {
        if(!authorizedPools[pool]) revert UnauthorizedPool();
        _;
    }

    /**
     * @notice Update Authorized Pool address
     * @param pool pool address
     */
    function addPool(address pool) external onlyOwner {
        authorizedPools[pool] = true;
    }

    /**
     * @notice Update index price for a pool (called by authorized oracle)
     * @param pool The pool address
     * @param newIndexPrice The new index price
     */
    function updateIndexPrice(address pool, uint256 newIndexPrice) external onlyOwner onlyPool(pool) {
        require(newIndexPrice > 0, "Invalid index price");
        oraclePrice[pool] = newIndexPrice;
        updateTime[pool] = block.timestamp;

        // Notify pool of price update
        IPool(pool).updateOraclePrice(newIndexPrice);

        emit IndexPriceUpdated(pool, newIndexPrice);
    }

    /**
     * @notice Record a trade for VTWAP calculation
     * @dev When a new trade matches, pool calls the oracle to update premium accumulator
     * @param size The matched trading size
     * @param price The matched trading price
     */
    function updatePoolInfo(uint256 size, uint256 price) external onlyPool(msg.sender) {

        uint256 timeWeight = block.timestamp - lastFundingTime;
        uint128 VTWeight = uint128(timeWeight * uint128(size));
        PoolFundingData memory data = poolData[msg.sender];
 
        // we use Mixed Volume-weighted and Time-weighted avg Price
        // VTWAP
        // Avg Price = \frac{\sum P_i * T_i * V_i}{ \sum T_i * V_i}
        // If oracle price was updated in last 2 min,
        // we assume that oracle can be used for premium price calculation 
        if( block.timestamp - updateTime[msg.sender] <= 120 ) {
            data.sampleCount++;
            data.cumWeight += VTWeight;
            data.cumWeightedPremium += uint128(price) * VTWeight;
            data.cumWeightedOracle += uint128(oraclePrice[msg.sender]) * VTWeight;
        }

        poolData[msg.sender] = data;

    }

    /**
     * @notice Calculate interest rate based on settlement period
     * @dev Interest Rate = 0.03% / (24 hours / Settlement Period)
     * @return interestRate Interest rate in basis points
     *
     * Example:
     * - 8 hour period: 0.03% / (24/8) = 0.03% / 3 = 0.01% = 1 bp
     * - 4 hour period: 0.03% / (24/4) = 0.03% / 6 = 0.005% = 0.5 bp
     */
    function calculateInterestRate() public view returns (int128 interestRate) {
        // BASE_RATE = 3 bp (0.03%)
        // periodsPerDay = 24 hours / settlementPeriod
        uint256 periodsPerDay = 24 hours / settlementPeriod;
        require(periodsPerDay > 0, "Invalid settlement period");

        // Interest Rate = BASE_RATE / periodsPerDay
        interestRate = BASE_RATE / int128( uint128(periodsPerDay) );

        return interestRate;
    }

    /**
     * @notice Calculate funding rate for a pool
     * @dev Formula: fundingRate = clamp[avgVTWAPDiff + clamp(interestRate - avgVTWAPDiff, 0.05%, -0.05%), cap, floor]
     * @param pool The pool address
     * @return avgVTWAPDiff Average VTWAP premium in basis points
     * @return interestRate Interest rate in basis points
     * @return fundingRate Final clamped funding rate in basis points
     */
    function calculateFundingRate(address pool)
        public
        view
        returns (
            int128 avgVTWAPDiff,
            int128 interestRate,
            int128 fundingRate
        )
    {
        // Step 1: Calculate average premium index
        uint128 avgVT;
        uint128 avgVTOracle;

        avgVT = getVTWAPIndex(pool);
        avgVTOracle = getVTWAPOracle(pool);
        avgVTWAPDiff = int128(avgVT - avgVTOracle) * BASIS_POINT / int128(avgVTOracle);

        // Step 2: Calculate interest rate based on settlement period
        interestRate = calculateInterestRate();

        // Step 3: Calculate (interestRate - avgVTWAPDiff)
        int128 interestDiff = interestRate - avgVTWAPDiff;

        // Step 4: Inner clamp - limit to [-0.05%, 0.05%] = [-5bp, 5bp]
        int128 clampedDiff = clamp(interestDiff, -CLAMP_RANGE, CLAMP_RANGE);

        // Step 5: Add to average premium index
        int128 rawFundingRate = avgVTWAPDiff + clampedDiff;

        // Step 6: Outer clamp - limit to [floor, cap]
        fundingRate = clamp(rawFundingRate, fundingRateFloor, fundingRateCap);

        return (avgVTWAPDiff, interestRate, fundingRate);
    }

    /**
     * @notice Apply funding rate to pool and reset accumulator
     * @dev Should be called at the end of each settlement period
     * @param pool The pool address
     */
    function applyFundingRate(address pool) external onlyOwner onlyPool(pool){
        require(block.timestamp >= lastFundingTime + settlementPeriod, "Settlement period not reached");

        (int256 avgVTWAPRate, int256 interestRate, int256 fundingRate) = calculateFundingRate(pool);

        // Convert funding rate to funding index change
        // fundingIdx accumulates price-proportional funding:
        //   change = oraclePrice * fundingRate / BASIS_POINT
        // Positive fundingRate → longs pay shorts (fundingIdx increases)
        // Negative fundingRate → shorts pay longs (fundingIdx decreases)
        uint256 currentFundingIdx = IPool(pool).fundingIdx();
        int256 fundingChange = int256(oraclePrice[pool]) * fundingRate / BASIS_POINT;
        uint256 newFundingIdx;
        if (int256(currentFundingIdx) + fundingChange > 0) {
            newFundingIdx = uint256(int256(currentFundingIdx) + fundingChange);
        } else {
            newFundingIdx = 0;
        }

        // Update pool's funding index
        IPool(pool).updateFundingIndex(newFundingIdx);

        // Reset accumulators for next period
        delete poolData[pool];
        lastFundingTime = block.timestamp;

        emit FundingRateCalculated(pool, fundingRate, avgVTWAPRate, interestRate);
    }

    /**
     * @notice Get average premium index for a pool
     * @dev Avg Premium Index = cumWeightedPremium / cumWeight
     * @param pool The pool address
     * @return Average premium index in basis points
     */
    function getVTWAPIndex(address pool) public view returns (uint128) {
        PoolFundingData memory data = poolData[pool];
        if (data.cumWeight == 0) return 0;
        return data.cumWeightedPremium / data.cumWeight;
    }

    /**
     * @notice Get average premium oracle px for a pool
     * @dev Avg Premium Oracle px = cumWeightedOracle / cumWeight
     * @param pool The pool address
     * @return Average premium index in basis points
     */
    function getVTWAPOracle(address pool) public view returns (uint128) {
        PoolFundingData memory data = poolData[pool];
        if (data.cumWeight == 0) return 0;
        return data.cumWeightedOracle / data.cumWeight;
    }

    /**
     * @notice Get premium data statistics
     * @param pool The pool address
     * @return sampleCount Number of samples collected
     * @return avgVTWAPIndex Average premium index
     */
    function getPoolsStats(address pool)
        external
        view
        returns (uint64 sampleCount, uint128 avgVTWAPIndex)
    {
        PoolFundingData memory data = poolData[pool];
        return (data.sampleCount, getVTWAPIndex(pool));
    }

    /**
     * @notice Clamp a value between min and max
     * @param value The value to clamp
     * @param min Minimum value
     * @param max Maximum value
     * @return Clamped value
     */
    function clamp(int128 value, int128 min, int128 max) 
        internal 
        pure 
        returns (int128) 
    {
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }

    /**
     * @notice Update funding rate limits
     * @param newCap New funding rate cap (in basis points)
     * @param newFloor New funding rate floor (in basis points)
     */
    function setFundingRateLimits(int128 newCap, int128 newFloor) external onlyOwner {
        require(newCap > newFloor, "Cap must be greater than floor");
        fundingRateCap = newCap;
        fundingRateFloor = newFloor;
    }

}