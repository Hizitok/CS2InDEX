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
    error InvalidOracle();
    error InvalidStatus();
    error NotAuthorized();
    error InvalidOrder();

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

    // ── Emergency Pause ───────────────────────────────────────────────────────

    /** @notice Pause new order creation (owner only) */
    function pause() external;

    /** @notice Resume new order creation (owner only) */
    function unpause() external;

    /** @notice Returns true when the pool is paused */
    function paused() external view returns (bool);

    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Create a new order
     * @param margin margin amount
     * @param pOrder Order details
     * @return newPosId The created order/position ID
     */
    function newOrder(uint256 margin, PoolOrder memory pOrder) external returns (OrderId newPosId);

    /**
     * @notice Cancel an open order
     * @param orderId Order ID to cancel
     */
    function cancelOrder(OrderId orderId) external returns (bool);

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
     * @notice Collect accumulated fees (owner only)
     * @param to Recipient address
     */
    function collectFees(address to) external;

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
     * @return Max leverage (1000 = 10x)
     */
    function maxLeverage() external view returns (uint256);

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
     * @notice Update oracle price (owner only)
     * @param newPrice New price multiplied by 100
     */
    function updateOraclePrice(uint256 newPrice) external;

    /**
     * @notice Get current funding index
     * @return Current funding index
     */
    function fundingIdx() external view returns (uint256);

    /**
     * @notice Update new Funding Index
     * @param newFundingIdx New Funding Index
     */
    function updateFundingIndex(uint256 newFundingIdx) external;

    /**
     * @notice Get position NFT contract address
     * @return Position NFT address
     */
    function positionNFT() external view returns (address);

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

    function setEngine(address _engine) external;

    /**
     * @notice Get pool description and last price
     */
    function getPoolInfo() external view returns (string memory description, uint256 lastPrice);

    /**
     * @notice Set authorized Router address (owner only)
     */
    function setRouter(address _router) external;

    /**
     * @notice Create a new order on behalf of a trader (Router only)
     * @param trader The actual trader; vault margin is pulled from their balance and NFT minted to them
     * @param margin Margin amount
     * @param pOrder Order details
     * @return newPosId The created position ID
     */
    function newOrderFor(address trader, uint256 margin, PoolOrder memory pOrder) external returns (OrderId newPosId);

    /**
     * @notice Get liquidation engine address
     * @return Engine address
     */
    function engine() external view returns (address);

    /**
     * @notice Force liquidate a position (engine only)
     * @dev Skips auth/price checks; places limit order at bankruptcy price
     * @param orderId Position ID to liquidate
     * @param pOrder Closing order (Limit at bankruptcy price)
     */
    function forceLiquidate(OrderId orderId, PoolOrder memory pOrder) external;

    /**
     * @notice Emergency close all listed positions at oracle price (owner only)
     * @dev Pauses the pool, then force-closes each position ID provided.
     *      Position IDs must be supplied by an off-chain indexer.
     * @param positionIds Open position IDs to force-close
     */
    function emergencyCloseAllPositions(OrderId[] calldata positionIds) external;

    /**
     * @notice Get order book depth for depth chart display
     * @param nLevels Maximum number of distinct price levels per side
     * @return askPrices Sell-side price levels (ascending, best ask first)
     * @return askSizes  Total open size at each ask price level
     * @return bidPrices Buy-side price levels (descending, best bid first)
     * @return bidSizes  Total open size at each bid price level
     */
    function getDepth(uint256 nLevels) external view returns (
        uint256[] memory askPrices,
        uint256[] memory askSizes,
        uint256[] memory bidPrices,
        uint256[] memory bidSizes
    );

}
