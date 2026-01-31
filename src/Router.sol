// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IRouter.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IPosition.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IERC20.sol";
import "./libraries/ReentrancyGuard.sol";

/**
 * @title Router
 * @notice Router contract for convenient interaction with CS2InDEX protocol
 * @dev Provides batch operations and combined functions for better UX
 */
contract Router is IRouter, ReentrancyGuard {
    IVault public immutable vault;
    IFactory public immutable factory;
    IERC20 public immutable currency;

    constructor(address _vault, address _factory, address _currency) {
        require(_vault != address(0), "Invalid vault");
        require(_factory != address(0), "Invalid factory");
        require(_currency != address(0), "Invalid currency");

        vault = IVault(_vault);
        factory = IFactory(_factory);
        currency = IERC20(_currency);
    }

    /**
     * @notice Deposit Token to vault and open position in one tx
     */
    function depositAndOpenPosition(
        address pool,
        uint256 depositAmount,
        PoolOrder calldata order
    ) external nonReentrant returns (OrderId orderId) {
        require(isValidPool(pool), "Invalid pool");
        require(depositAmount > 0, "Invalid deposit amount");

        // Transfer Token from user to this contract
        currency.transferFrom(msg.sender, address(this), depositAmount);

        // Approve vault to spend Token
        currency.approve(address(vault), depositAmount);

        // Deposit to vault
        vault.deposit(depositAmount);

        // Transfer deposited balance to user's vault account
        vault.internalTransfer(address(this), msg.sender, depositAmount);

        // Open position
        orderId = IPool(pool).newOrder(order);

        emit PositionOpened(msg.sender, pool, orderId, order.size);
    }

    /**
     * @notice Close position and withdraw all available balance
     */
    function closePositionAndWithdraw(
        address pool,
        OrderId positionId,
        PoolOrder calldata closeOrder
    ) external nonReentrant returns (uint256 withdrawn) {
        require(isValidPool(pool), "Invalid pool");

        // Close position
        IPool(pool).closePosition(positionId, closeOrder);

        // Settle PnL
        IPool(pool).settlePnL(positionId);

        // Get available balance
        uint256 available = vault.availableBalance(msg.sender);

        // Withdraw all available
        if (available > 0) {
            vault.withdraw(available);
            withdrawn = available;
        }

        emit PositionClosed(msg.sender, pool, positionId, 0);
    }

    /**
     * @notice Open positions in multiple pools atomically
     */
    function batchOpenPositions(
        address[] calldata pools,
        PoolOrder[] calldata orders
    ) external nonReentrant returns (OrderId[] memory orderIds) {
        require(pools.length == orders.length, "Length mismatch");
        require(pools.length > 0, "Empty arrays");

        orderIds = new OrderId[](pools.length);

        for (uint256 i = 0; i < pools.length; i++) {
            require(isValidPool(pools[i]), "Invalid pool");
            orderIds[i] = IPool(pools[i]).newOrder(orders[i]);
            emit PositionOpened(msg.sender, pools[i], orderIds[i], orders[i].size);
        }

        emit BatchOperationCompleted(msg.sender, pools.length, pools.length);
    }

    /**
     * @notice Close multiple positions atomically
     */
    function batchClosePositions(
        address[] calldata pools,
        OrderId[] calldata positionIds,
        PoolOrder[] calldata closeOrders
    ) external nonReentrant returns (bool[] memory success) {
        require(pools.length == positionIds.length, "Length mismatch");
        require(pools.length == closeOrders.length, "Length mismatch");
        require(pools.length > 0, "Empty arrays");

        success = new bool[](pools.length);
        uint256 successCount = 0;

        for (uint256 i = 0; i < pools.length; i++) {
            if (!isValidPool(pools[i])) {
                success[i] = false;
                continue;
            }

            try IPool(pools[i]).closePosition(positionIds[i], closeOrders[i]) {
                IPool(pools[i]).settlePnL(positionIds[i]);
                success[i] = true;
                successCount++;
                emit PositionClosed(msg.sender, pools[i], positionIds[i], 0);
            } catch {
                success[i] = false;
            }
        }

        emit BatchOperationCompleted(msg.sender, successCount, pools.length);
    }

    /**
     * @notice Cancel multiple orders atomically
     */
    function batchCancelOrders(
        address[] calldata pools,
        OrderId[] calldata orderIds
    ) external nonReentrant returns (bool[] memory success) {
        require(pools.length == orderIds.length, "Length mismatch");
        require(pools.length > 0, "Empty arrays");

        success = new bool[](pools.length);
        uint256 successCount = 0;

        for (uint256 i = 0; i < pools.length; i++) {
            if (!isValidPool(pools[i])) {
                success[i] = false;
                continue;
            }

            try IPool(pools[i]).cancelOrder(orderIds[i]) {
                success[i] = true;
                successCount++;
            } catch {
                success[i] = false;
            }
        }

        emit BatchOperationCompleted(msg.sender, successCount, pools.length);
    }

    /**
     * @notice Get all user positions across all pools
     */
    function getUserPositionsAcrossAllPools(address user)
        external
        view
        returns (Position[] memory positions, address[] memory poolAddresses)
    {
        address[] memory allPools = factory.getAllPools();

        // Count total positions across all pools
        uint256 totalPositions = 0;
        uint256[][] memory poolPositionIds = new uint256[][](allPools.length);

        for (uint256 i = 0; i < allPools.length; i++) {
            // This would require position enumeration
            // For now, return empty - implementation pending
        }

        // Return empty arrays - full implementation requires position enumeration
        positions = new Position[](0);
        poolAddresses = new address[](0);
    }

    /**
     * @notice Get total margin across all pools
     */
    function getTotalMarginAcrossAllPools(address user) external view returns (uint256 totalMargin) {
        // Full implementation requires position enumeration
        return 0;
    }

    /**
     * @notice Get total unrealized PnL
     */
    function getTotalUnrealizedPnL(address user) external view returns (int256 totalPnL) {
        // Full implementation requires position enumeration and PnL calculation
        return 0;
    }

    /**
     * @notice Emergency close all positions
     */
    function emergencyCloseAllPositions(address user, address[] calldata pools)
        external
        nonReentrant
        returns (uint256 closed)
    {
        require(msg.sender == user, "Can only close own positions");

        for (uint256 i = 0; i < pools.length; i++) {
            if (!isValidPool(pools[i])) continue;

            // Full implementation requires position enumeration
        }

        emit EmergencyCloseExecuted(user, closed);
        return closed;
    }

    /**
     * @notice Check if pool is valid
     */
    function isValidPool(address pool) public view returns (bool) {
        return factory.isValidPool(pool);
    }
}



