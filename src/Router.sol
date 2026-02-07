// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IRouter.sol";
import "./interfaces/IPool.sol";
import {IVault} from"./interfaces/IVault.sol";
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
    address public immutable vault;
    address public immutable factory;
    IERC20 public immutable currency;

    constructor(address _vault, address _factory, address _currency) {
        require(_vault != address(0), "Invalid vault");
        require(_factory != address(0), "Invalid factory");
        require(_currency != address(0), "Invalid currency");

        vault = _vault;
        factory = _factory;
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
        currency.approve( vault, depositAmount);

        // Deposit to vault
        IVault(vault).deposit(depositAmount);

        // Transfer deposited balance to user's vault account
        IVault(vault).internalTransfer(address(this), msg.sender, depositAmount);

        // Open position
        orderId = IPool(pool).newOrder(depositAmount, order);

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
        uint256 available = IVault(vault).balanceOf(msg.sender);

        // Withdraw all available
        if (available > 0) {
            IVault(vault).withdraw(available);
            withdrawn = available;
        }

        emit PositionClosed(msg.sender, pool, positionId, 0);
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
        return IFactory(factory).isValidPool(pool);
    }
}



