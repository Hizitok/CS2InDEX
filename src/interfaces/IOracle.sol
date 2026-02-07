// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IOracle
 * @notice Interface for CS2 Index Oracle
 * @dev Provides price feeds for CS2 indices from external sources
 */
interface IOracle {

    function addPool(address pool) external;

    function oraclePrice(address pool) external view returns (uint256);

    function updateTime(address pool) external view returns (uint256);

    /**
     * @notice Update oracle price
     * @param newPrice New price multiplied by 100
     * @dev Only callable by authorized price feeders or owner
     */
    function updateIndexPrice(address pool, uint256 newPrice) external;

    function updatePoolInfo(uint256 size, uint256 price) external;

    function calculateInterestRate() external view returns (int128 interestRate);

    function calculateFundingRate(address pool)
        external
        view
    returns (
        int128 avgVTWAPDiff,
        int128 interestRate,
        int128 fundingRate
    );

    function applyFundingRate(address pool) external;

    function getVTWAPIndex(address pool) external view returns (uint128);

    function getVTWAPOracle(address pool) external view returns (uint128);

    function getPoolsStats(address pool)
        external
        view
    returns (uint64 sampleCount, uint128 avgVTWAPIndex);

    function setFundingRateLimits(int128 newCap, int128 newFloor) external;

    // Events
    event FundingRateCalculated(address indexed pool, int256 fundingRate, int256 avgVTWAPIndex, int256 interestRate);
    event IndexPriceUpdated(address indexed pool, uint256 newPrice);
    event VTWAPIndexSampled(address indexed pool, int256 VTWAPIndex, uint256 weight);
    event SettlementPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

}
