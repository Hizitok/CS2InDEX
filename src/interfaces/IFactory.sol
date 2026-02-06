// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFactory
 * @notice Interface for CS2InDEX Factory
 * @dev Deploys and manages trading pools for CS2 item indices
 */
interface IFactory {

    struct PoolInfo {
        address pool;
        address engine;
        string itemName;
        uint256 deployedAt;
        bool active;
    }

    function createPool(
        string memory itemName,
        uint256 initialPrice,
        uint256 pxDecimals
    ) external returns (address pool, address engine);

    function setPoolStatus(address pool, bool active) external;

    function updatePrice(address pool, uint256 newPrice) external;

    // Shared contracts
    function vault() external view returns (address);
    function oracle() external view returns (address);
    function nft() external view returns (address);
    function getPoolInfo(address pool) external view returns (PoolInfo memory);
    function poolCount() external view returns (uint256);
    function getAllPools() external view returns (address[] memory);
    function isValidPool(address pool) external view returns (bool);

    // Events
    event PoolCreated(address indexed pool, address engine, string itemName, uint256 initialPrice);
    event PoolStatusChanged(address indexed pool, bool active);
    event OraclePriceUpdated(address indexed pool, uint256 newPrice);
}
