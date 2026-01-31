// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OrderTypes} from "./OrderTypes.sol";

/**
 * @title IADLEngine
 * @notice Interface for the Auto-Deleveraging (ADL) Engine
 * @dev Manages emergency position closures when insurance fund is depleted
 */
interface IADLEngine is OrderTypes {
    /**
     * @notice Set pool authorization
     * @param pool Pool address
     * @param authorized Authorization status
     */
    function setPool(address pool, bool authorized) external;

    /**
     * @notice Set liquidation engine address
     * @param liquidation Liquidation engine address
     */
    function setLiquidationEngine(address liquidation) external;

    /**
     * @notice Execute ADL to deleverage positions
     * @param pool Pool address
     * @param targetAmount Target amount to deleverage (in USDC)
     */
    function executeADL(address pool, uint256 targetAmount) external;

    /**
     * @notice Build ADL queue for a pool
     * @param pool Pool address
     * @dev Sorts positions by profitability and leverage for ADL priority
     */
    function buildADLQueue(address pool) external;

    /**
     * @notice Add position to ADL queue
     * @param pool Pool address
     * @param orderId Position ID to add
     */
    function addToADLQueue(address pool, OrderId orderId) external;

    /**
     * @notice Get ADL queue length for a pool
     * @param pool Pool address
     * @return Queue length
     */
    function getADLQueueLength(address pool) external view returns (uint256);

    /**
     * @notice Get ADL queue for a pool
     * @param pool Pool address
     * @return Array of position IDs in ADL order
     */
    function getADLQueue(address pool) external view returns (OrderId[] memory);

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
     * @notice Check if pool is authorized
     * @param pool Pool address
     * @return True if authorized
     */
    function isAuthorizedPool(address pool) external view returns (bool);

    // Events
    event ADLExecuted(
        address indexed pool,
        OrderId indexed orderId,
        address indexed trader,
        uint256 size,
        int256 pnl
    );
    event ADLQueueBuilt(address indexed pool, uint256 queueLength);
    event ADLPositionAdded(address indexed pool, OrderId indexed orderId);
}
