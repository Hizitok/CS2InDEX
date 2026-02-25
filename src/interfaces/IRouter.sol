// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OrderTypes} from "./OrderTypes.sol";

/**
 * @title IRouter
 * @notice Interface for the CS2InDEX Router — single entry-point for all user trading.
 */
interface IRouter is OrderTypes {

    // ── Structs ───────────────────────────────────────────────────────────────

    struct PositionView {
        address  pool;
        OrderId  posId;
        Position pos;
        uint256  oraclePrice;
    }

    struct MarketInfo {
        address pool;
        string  description;
        uint256 lastPrice;
        uint256 oraclePrice;
        uint256 ask1Price;
        uint256 bid1Price;
        uint256 fundingIdx;
        uint256 maxLeverage;
    }

    // ── Events ────────────────────────────────────────────────────────────────

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event PositionOpened(address indexed pool, address indexed trader, OrderId posId);
    event PositionClosed(address indexed pool, address indexed trader, OrderId orderId);
    event OrderCancelled(address indexed pool, address indexed trader, OrderId orderId);

    // ── Vault Helpers ─────────────────────────────────────────────────────────

    /// @notice Deposit USDC into vault. Requires USDC.approve(router, amount).
    function deposit(uint256 amount) external;

    /// @notice Withdraw USDC from vault to caller.
    function withdraw(uint256 amount) external;

    // ── Core Trading ──────────────────────────────────────────────────────────

    /**
     * @notice Deposit USDC and open a position in one transaction.
     * @dev Requires USDC.approve(router, depositAmount).
     */
    function depositAndOpen(
        address pool,
        uint256 depositAmount,
        uint256 margin,
        PoolOrder calldata order
    ) external returns (OrderId posId);

    /**
     * @notice Open a position using existing vault balance.
     */
    function open(
        address pool,
        uint256 margin,
        PoolOrder calldata order
    ) external returns (OrderId posId);

    /**
     * @notice Close an open position.
     * @dev Requires positionNFT.setApprovalForAll(router, true).
     */
    function close(
        address pool,
        OrderId orderId,
        PoolOrder calldata closeOrder
    ) external;

    /**
     * @notice Cancel a pending order and reclaim margin.
     * @dev Requires positionNFT.setApprovalForAll(router, true).
     */
    function cancel(address pool, OrderId orderId) external returns (bool);

    // ── Batch Operations ──────────────────────────────────────────────────────

    function batchOpen(
        address[]   calldata pools,
        uint256[]   calldata margins,
        PoolOrder[] calldata orders
    ) external returns (OrderId[] memory posIds);

    function batchClose(
        address[]   calldata pools,
        OrderId[]   calldata orderIds,
        PoolOrder[] calldata closeOrders
    ) external;

    // ── View ──────────────────────────────────────────────────────────────────

    function getPortfolio(address user) external view returns (PositionView[] memory);
    function getAllMarkets()             external view returns (MarketInfo[]   memory);
    function getMarketInfo(address pool) external view returns (MarketInfo    memory);
    function getBalance(address user)    external view returns (uint256);

    // ── Immutables ────────────────────────────────────────────────────────────

    function factory() external view returns (address);
    function vault()   external view returns (address);
    function nft()     external view returns (address);
    function usdc()    external view returns (address);
}
