// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OrderTypes} from "./OrderTypes.sol";

/**
 * @title IPool
 * @notice Interface for CS2InDEX Trading Pool
 * @dev Manages order book, matching, and position lifecycle
 */
interface IPool is OrderTypes {
    // Errors
    error FOK();
    error PxOverflow();
    error PxUnderflow();
    error LeverageOverflow();
    error CancelFailed();
    error InvalidMatch();
    error InvaildStatus();
    error NotAuthorized();

    // Events
    event IOC();
    event MARKET();
    event ORDER_FILLED();
    event OrderCreated(OrderId indexed orderId, address indexed trader, bool isSell, uint256 size, uint256 price);
    event OrderMatched(OrderId indexed orderId, OrderId indexed matchedOrderId, uint256 size, uint256 price);
    event OrderCancelled(OrderId indexed orderId, address indexed trader);
    event PositionClosed(OrderId indexed orderId, address indexed trader, int256 pnl);
    event PnLSettled(OrderId indexed orderId, address indexed trader, int256 pnl, uint256 fees);
    event FeesCollected(address indexed collector, uint256 amount);
    event OraclePriceUpdated(uint256 oldPrice, uint256 newPrice);

    /**
     * @notice Create a new order
     * @param pOrder Order details
     * @return newPosId The created order/position ID
     */
    function newOrder(PoolOrder memory pOrder) external returns (OrderId newPosId);

    /**
     * @notice Cancel an open order
     * @param orderId Order ID to cancel
     */
    function cancelOrder(OrderId orderId) external;

    /**
     * @notice Close an existing position
     * @param orderId Position ID to close
     * @param pOrder Close order details
     * @return newPosId The order ID for closing
     */
    function closePosition(OrderId orderId, PoolOrder memory pOrder) external returns (OrderId newPosId);

    /**
     * @notice Settle PnL for a closed position
     * @param orderId Position ID
     */
    function settlePnL(OrderId orderId) external;

    /**
     * @notice Update oracle price (owner only)
     * @param newPrice New price multiplied by 100
     */
    function updateOraclePrice(uint256 newPrice) external;

    /**
     * @notice Collect accumulated fees (owner only)
     * @param to Recipient address
     */
    function collectFees(address to) external;

    /**
     * @notice Get total fees collected
     * @return Total fees
     */
    function feeCollected() external view returns (uint256);

    /**
     * @notice Get comprehensive pool information
     * @return _lastPriceX100 Last traded price
     * @return _ask1Price Total trading volume
     * @return _bid1Price Total fees collected
     */
    function getOrderbookInfo()
        external
        view
        returns (
            uint256 _lastPriceX100,
            uint256 _ask1Price,
            uint256 _bid1Price
        );

    /**
     * @notice Get maximum leverage allowed
     * @return Max leverage (600 = 6x)
     */
    function MAX_LEVERAGE() external view returns (uint256);

    /**
     * @notice Get oracle contract address
     * @return Oracle address
     */
    function oracle() external view returns (address);

    /**
     * @notice Get current oracle price
     * @return Oracle price multiplied by 100
     */
    function oraclePrice() external view returns (uint256);

    /**
     * @notice Get position NFT contract address
     * @return Position NFT address
     */
    function positionNFT() external view returns (address);

    /**
     * @notice Get total trading volume
     * @return Total volume
     */
    function totalVolume() external view returns (uint256);

    /**
     * @notice Get vault contract address
     * @return Vault address
     */
    function vault() external view returns (address);

    /**
     * @notice Get last traded price
     * @return Last price multiplied by 100
     */
    function getLastPrice() external view returns (uint256);

}
