// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OrderTypes} from "./OrderTypes.sol";

/**
 * @title IRouter
 * @notice Interface for the CS2InDEX Router contract
 * @dev Router provides convenient functions for interacting with multiple pools
 *      and performing batch operations
 */
interface IRouter is OrderTypes {
    /**
     * @notice Deposit USDC to vault and open a position in one transaction
     * @param pool Pool address
     * @param depositAmount Amount of USDC to deposit
     * @param order Order details
     * @return orderId The created order/position ID
     */
    function depositAndOpenPosition(
        address pool,
        uint256 depositAmount,
        PoolOrder calldata order
    ) external returns (OrderId orderId);

    /**
     * @notice Close position and withdraw all available balance
     * @param pool Pool address
     * @param positionId Position to close
     * @param closeOrder Close order details
     * @return withdrawn Amount withdrawn
     */
    function closePositionAndWithdraw(
        address pool,
        OrderId positionId,
        PoolOrder calldata closeOrder
    ) external returns (uint256 withdrawn);

    /**
     * @notice Emergency close all positions for a user
     * @param user User address
     * @param pools Array of pool addresses
     * @return closed Number of positions closed
     */
    function emergencyCloseAllPositions(address user, address[] calldata pools)
        external
        returns (uint256 closed);

    /**
     * @notice Get the vault address
     * @return Address of the vault contract
     */
    function vault() external view returns (address);

    /**
     * @notice Get the factory address
     * @return Address of the factory contract
     */
    function factory() external view returns (address);

    /**
     * @notice Check if a pool is valid and active
     * @param pool Pool address
     * @return isValid True if pool is valid and active
     */
    function isValidPool(address pool) external view returns (bool isValid);

    // Events
    event PositionOpened(address indexed user, address indexed pool, OrderId indexed orderId, uint256 size);
    event PositionClosed(address indexed user, address indexed pool, OrderId indexed orderId, int256 pnl);
    event BatchOperationCompleted(address indexed user, uint256 successCount, uint256 totalCount);
    event EmergencyCloseExecuted(address indexed user, uint256 positionsClosed);
}
