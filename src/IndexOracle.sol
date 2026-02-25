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

    // Maximum time interval counted per trade in the weighted average.
    // A single price point that persists longer than this is capped, preventing one
    // stale or illiquid period from monopolising the entire period's weight.
    uint256 public constant MAX_TRADE_INTERVAL = 1 hours;

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
        // EVM Slot 0  (64 + 64 + 128 = 256 bits)
        uint64 lastFundingTime;    // Timestamp of last funding settlement for this pool
        uint64 lastTradeTime;      // Timestamp of last on-chain trade (for inter-trade Δt)
        uint128 cumWeight;         // Cumulative Σ min(Δt, cap) × size
        // EVM Slot 1  (128 + 128 = 256 bits)
        uint128 cumWeightedPremium;  // Cumulative Σ price × weight
        uint128 cumWeightedOracle;   // Cumulative Σ oraclePrice × weight
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
        // Initialise per-pool timestamps so the first trade gets a zero Δt
        // instead of the full time elapsed since the contract was deployed.
        poolData[pool].lastFundingTime = uint64(block.timestamp);
        poolData[pool].lastTradeTime   = uint64(block.timestamp);
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

        PoolFundingData memory data = poolData[msg.sender];

        // Inter-trade time weight: how long the previous price persisted before this trade.
        // Capped at MAX_TRADE_INTERVAL so one very long illiquid gap can't dominate the
        // whole settlement period's weight.
        uint256 dt = block.timestamp - data.lastTradeTime;
        uint256 cappedDt = dt > MAX_TRADE_INTERVAL ? MAX_TRADE_INTERVAL : dt;

        // Always advance lastTradeTime so the next trade measures from now.
        data.lastTradeTime = uint64(block.timestamp);

        // Only accumulate into the premium index when the oracle price is fresh
        // (updated within the last 2 minutes). Stale oracle → skip accumulation
        // but still advance lastTradeTime so we don't carry a stale gap forward.
        if (block.timestamp - updateTime[msg.sender] <= 120) {
            // weight = min(Δt, cap) × size  — computed in uint256 to avoid overflow
            uint256 vtWeight256 = cappedDt * size;
            uint128 VTWeight = vtWeight256 > type(uint128).max
                ? type(uint128).max
                : uint128(vtWeight256);

            // Weighted products in uint256 before capping to uint128 accumulator fields
            uint256 weightedPremium = uint256(price)                   * uint256(VTWeight);
            uint256 weightedOracle  = uint256(oraclePrice[msg.sender]) * uint256(VTWeight);

            uint256 newCumWeight = uint256(data.cumWeight) + uint256(VTWeight);
            data.cumWeight = newCumWeight > type(uint128).max
                ? type(uint128).max
                : uint128(newCumWeight);

            uint256 newCumPremium = uint256(data.cumWeightedPremium) + weightedPremium;
            data.cumWeightedPremium = newCumPremium > type(uint128).max
                ? type(uint128).max
                : uint128(newCumPremium);

            uint256 newCumOracle = uint256(data.cumWeightedOracle) + weightedOracle;
            data.cumWeightedOracle = newCumOracle > type(uint128).max
                ? type(uint128).max
                : uint128(newCumOracle);
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

        // Guard: if no samples collected (oracle price stale or no trades), treat diff as 0.
        // Without this guard: avgVTOracle==0 causes div/0; avgVT < avgVTOracle causes
        // uint128 underflow and revert (bearish markets where VTWAP < index price).
        if (avgVTOracle == 0) {
            avgVTWAPDiff = 0;
        } else {
            // Use int256 intermediate to safely handle signed subtraction and overflow.
            int256 diff256 = int256(uint256(avgVT)) - int256(uint256(avgVTOracle));
            int256 raw = diff256 * int256(uint256(uint128(BASIS_POINT))) / int256(uint256(avgVTOracle));
            // Clamp to int128 range before storing (extreme outliers are bounded anyway by outer clamp)
            if (raw > type(int128).max) raw = type(int128).max;
            if (raw < type(int128).min) raw = type(int128).min;
            avgVTWAPDiff = int128(raw);
        }

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
        // Use per-pool lastFundingTime so each pool has an independent settlement period.
        // Previously the global `lastFundingTime` was used, which meant applying funding
        // to one pool would reset the timer for ALL other pools.
        uint64 poolLastTime = poolData[pool].lastFundingTime;
        require(block.timestamp >= poolLastTime + settlementPeriod, "Settlement period not reached");

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

        // Reset accumulators for next period; restore both timestamps so the next period
        // starts cleanly without carrying a stale gap from the previous period.
        delete poolData[pool];
        poolData[pool].lastFundingTime = uint64(block.timestamp);
        poolData[pool].lastTradeTime   = uint64(block.timestamp);

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
     * @return lastTradeTime Timestamp of the most recent on-chain trade
     * @return avgVTWAPIndex Current period's volume-time weighted average premium index
     */
    function getPoolsStats(address pool)
        external
        view
        returns (uint64 lastTradeTime, uint128 avgVTWAPIndex)
    {
        PoolFundingData memory data = poolData[pool];
        return (data.lastTradeTime, getVTWAPIndex(pool));
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