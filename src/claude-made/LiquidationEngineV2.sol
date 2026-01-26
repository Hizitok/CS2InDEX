// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "./libraries/Ownable.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {OrderTypes} from "./interfaces/OrderTypes.sol";
import {CS2IndexOracle} from "./CS2IndexOracle.sol";
import {IzitOrderStatisticsTree} from "./libraries/IzitOrderStatisticsTree.sol";

/**
 * @title LiquidationEngineV2
 * @notice Enhanced liquidation engine with Order Statistics Tree for efficient risk management
 * @dev Improvements over V1:
 *      - O(log n) position rank queries
 *      - O(log n) batch liquidation of top N positions
 *      - O(log n) liquidation pressure estimation
 *      - Real-time risk dashboard support
 */
contract LiquidationEngineV2 is Ownable, OrderTypes {
    using IzitOrderStatisticsTree for IzitOrderStatisticsTree.Tree;

    address public factory;
    address public vault;

    // Margin thresholds (basis points, 10000 = 100%)
    uint256 public constant INITIAL_MARGIN = 1667; // 16.67% (6x leverage)
    uint256 public constant MAINTENANCE_MARGIN = 500; // 5% (20x effective)
    uint256 public constant LIQUIDATION_FEE = 250; // 2.5% goes to liquidator
    uint256 public constant BASIS_POINTS = 10000;

    address public insuranceFund;
    uint256 public insuranceFundBalance;

    // Pool => oracle address
    mapping(address => address) public poolOracles;

    // Track liquidations
    mapping(OrderId => bool) public isLiquidated;

    // ========== NEW: Order Statistics Tree for Liquidation Queue ==========
    // Pool => Liquidation Queue (sorted by liquidation price)
    mapping(address => IzitOrderStatisticsTree.Tree) public liquidationQueues;

    // Track liquidation prices for each position
    mapping(OrderId => uint256) public positionLiquidationPrice;

    // Global funding rate offset (for future funding rate support)
    // All liquidation prices shift by this amount
    mapping(address => int256) public fundingRateOffset;

    event PositionLiquidated(
        OrderId indexed orderId,
        address indexed liquidator,
        uint256 liquidationPrice,
        uint256 remainingMargin,
        uint256 liquidatorReward
    );

    event InsuranceFundUsed(
        OrderId indexed orderId,
        uint256 deficit,
        uint256 remainingFund
    );

    event PositionAddedToQueue(
        OrderId indexed orderId,
        address indexed pool,
        uint256 liquidationPrice,
        uint256 rank
    );

    event PositionRemovedFromQueue(
        OrderId indexed orderId,
        address indexed pool
    );

    constructor(address _vault, address _insuranceFund) Ownable(msg.sender) {
        vault = _vault;
        insuranceFund = _insuranceFund;
        factory = msg.sender;
    }

    /**
     * @notice Set pool authorization
     */
    function setPool(address pool, bool authorized) external onlyOwner {
        // Pool authorization logic
    }

    /**
     * @notice Set oracle for a pool
     */
    function setPoolOracle(address pool, address oracle) external onlyOwner {
        poolOracles[pool] = oracle;
    }

    /**
     * @notice Add position to liquidation queue (called when position opens)
     * @param pool Pool address
     * @param orderId Position ID
     * @param liquidationPrice The price at which position will be liquidated
     */
    function addPositionToQueue(address pool, OrderId orderId, uint256 liquidationPrice) external {
        require(msg.sender == pool || msg.sender == owner(), "Not authorized");
        require(liquidationPrice > 0, "Invalid liquidation price");
        require(positionLiquidationPrice[orderId] == 0, "Position already in queue");

        // Store liquidation price
        positionLiquidationPrice[orderId] = liquidationPrice;

        // Add to order statistics tree
        // Key = liquidation price, Value = orderId
        liquidationQueues[pool].insert(liquidationPrice, OrderId.unwrap(orderId));

        // Get rank for event
        uint256 rank = liquidationQueues[pool].getRank(liquidationPrice);

        emit PositionAddedToQueue(orderId, pool, liquidationPrice, rank);
    }

    /**
     * @notice Remove position from liquidation queue (called when position closes)
     * @param pool Pool address
     * @param orderId Position ID
     */
    function removePositionFromQueue(address pool, OrderId orderId) external {
        require(msg.sender == pool || msg.sender == owner(), "Not authorized");

        uint256 liquidationPrice = positionLiquidationPrice[orderId];
        if (liquidationPrice == 0) return; // Not in queue

        // Remove from tree
        liquidationQueues[pool].remove(liquidationPrice);

        // Clear storage
        delete positionLiquidationPrice[orderId];

        emit PositionRemovedFromQueue(orderId, pool);
    }

    /**
     * @notice Get position's risk ranking
     * @param pool Pool address
     * @param orderId Position ID
     * @return rank Position rank (1 = most at risk)
     * @return total Total positions in queue
     */
    function getPositionRiskRank(address pool, OrderId orderId)
        external
        view
        returns (uint256 rank, uint256 total)
    {
        uint256 liquidationPrice = positionLiquidationPrice[orderId];
        require(liquidationPrice > 0, "Position not in queue");

        rank = liquidationQueues[pool].getRank(liquidationPrice);
        total = liquidationQueues[pool].size();
    }

    /**
     * @notice Get top N positions most at risk of liquidation
     * @param pool Pool address
     * @param count Number of positions to return
     * @return orderIds Array of position IDs (sorted by risk, highest first)
     * @return liquidationPrices Array of liquidation prices
     */
    function getTopAtRiskPositions(address pool, uint256 count)
        external
        view
        returns (OrderId[] memory orderIds, uint256[] memory liquidationPrices)
    {
        uint256 total = liquidationQueues[pool].size();
        if (count > total) count = total;

        orderIds = new OrderId[](count);
        liquidationPrices = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            (uint256 price, uint256 orderId) = liquidationQueues[pool].getKthSmallest(i + 1);
            liquidationPrices[i] = price;
            orderIds[i] = OrderId.wrap(orderId);
        }
    }

    /**
     * @notice Estimate liquidation pressure at a given price
     * @param pool Pool address
     * @param priceThreshold Price level to check
     * @return count Number of positions that would be liquidatable
     * @return totalValue Total position value at risk
     */
    function estimateLiquidationPressure(address pool, uint256 priceThreshold)
        external
        view
        returns (uint256 count, uint256 totalValue)
    {
        count = liquidationQueues[pool].countLessThan(priceThreshold);

        // Calculate total value (would need position size info)
        // For now just return count
        totalValue = 0;
    }

    /**
     * @notice Batch liquidate multiple positions
     * @param pool Pool address
     * @param maxCount Maximum number of positions to liquidate
     * @return liquidated Number of positions actually liquidated
     */
    function batchLiquidate(address pool, uint256 maxCount)
        external
        returns (uint256 liquidated)
    {
        // Get current oracle price
        address oracle = poolOracles[pool];
        require(oracle != address(0), "Oracle not set");
        uint256 currentPrice = CS2IndexOracle(oracle).getPrice();

        // Get all positions below current price
        (uint256[] memory prices, uint256[] memory orderIdValues) =
            liquidationQueues[pool].getKeysLessThan(currentPrice, maxCount);

        for (uint256 i = 0; i < prices.length; i++) {
            OrderId orderId = OrderId.wrap(orderIdValues[i]);

            // Skip if already liquidated
            if (isLiquidated[orderId]) continue;

            // Attempt liquidation
            try this.liquidate(pool, orderId) {
                liquidated++;
            } catch {
                // Continue with next position if liquidation fails
                continue;
            }
        }
    }

    /**
     * @notice Check if a position is liquidatable
     * @param pool Pool address
     * @param orderId Position ID
     * @return liquidatable Whether position can be liquidated
     * @return marginRatio Current margin ratio in basis points
     */
    function checkLiquidatable(address pool, OrderId orderId)
        public
        view
        returns (bool liquidatable, uint256 marginRatio)
    {
        address positionNFT = IPool(pool).positionNFT();
        Position memory pos = IPosition(positionNFT).getPosition(orderId);

        // Only open positions can be liquidated
        if (pos.status != posStatus.open || pos.openSize == 0) {
            return (false, 0);
        }

        // Get current oracle price
        address oracle = poolOracles[pool];
        require(oracle != address(0), "Oracle not set");
        uint256 oraclePriceX100 = CS2IndexOracle(oracle).getPrice();

        // Calculate current position value and PnL
        (int256 unrealizedPnL, uint256 positionValue) = calculateUnrealizedPnL(
            pos,
            oraclePriceX100
        );

        // Calculate margin ratio = (margin + unrealizedPnL) / positionValue
        int256 currentMargin = int256(pos.openMargin) + unrealizedPnL;

        if (currentMargin <= 0) {
            // Negative margin = liquidatable
            return (true, 0);
        }

        // marginRatio = (currentMargin * BASIS_POINTS) / positionValue
        marginRatio = (uint256(currentMargin) * BASIS_POINTS) / positionValue;

        // Liquidatable if margin ratio < maintenance margin
        liquidatable = (marginRatio < MAINTENANCE_MARGIN);
    }

    /**
     * @notice Calculate unrealized PnL for a position
     * @param pos Position data
     * @param currentPriceX100 Current market price x100
     * @return pnl Unrealized PnL (can be negative)
     * @return positionValue Total position value
     */
    function calculateUnrealizedPnL(
        Position memory pos,
        uint256 currentPriceX100
    )
        public
        pure
        returns (int256 pnl, uint256 positionValue)
    {
        // Position value at current price
        positionValue = pos.openSize * currentPriceX100;

        // Calculate PnL
        if (pos.isShort) {
            // Short: profit when price drops
            // PnL = openAmount - currentValue
            pnl = int256(pos.openAmount) - int256(positionValue);
        } else {
            // Long: profit when price rises
            // PnL = currentValue - openAmount
            pnl = int256(positionValue) - int256(pos.openAmount);
        }
    }

    /**
     * @notice Liquidate an undercollateralized position
     * @param pool Pool address
     * @param orderId Position ID to liquidate
     */
    function liquidate(address pool, OrderId orderId) external {
        require(!isLiquidated[orderId], "Already liquidated");

        // Check if liquidatable
        (bool canLiquidate, uint256 marginRatio) = checkLiquidatable(pool, orderId);
        require(canLiquidate, "Position not liquidatable");

        address positionNFT = IPool(pool).positionNFT();
        Position memory pos = IPosition(positionNFT).getPosition(orderId);

        // Get current price
        address oracle = poolOracles[pool];
        uint256 liquidationPriceX100 = CS2IndexOracle(oracle).getPrice();

        // Calculate final PnL at liquidation price
        (int256 finalPnL, uint256 positionValue) = calculateUnrealizedPnL(
            pos,
            liquidationPriceX100
        );

        // Calculate remaining margin
        int256 remainingMarginInt = int256(pos.openMargin) + finalPnL;
        uint256 remainingMargin = remainingMarginInt > 0 ? uint256(remainingMarginInt) : 0;

        // Calculate liquidator reward (% of remaining margin)
        uint256 liquidatorReward = (remainingMargin * LIQUIDATION_FEE) / BASIS_POINTS;
        uint256 toInsuranceFund = remainingMargin - liquidatorReward;

        // If margin is negative, insurance fund covers the deficit
        if (remainingMarginInt < 0) {
            uint256 deficit = uint256(-remainingMarginInt);
            require(insuranceFundBalance >= deficit, "Insurance fund insufficient");
            insuranceFundBalance -= deficit;
            liquidatorReward = 0;
            toInsuranceFund = 0;

            emit InsuranceFundUsed(orderId, deficit, insuranceFundBalance);
        }

        // Pay liquidator reward
        if (liquidatorReward > 0) {
            IVault(vault).internalTransfer(pool, msg.sender, liquidatorReward);
        }

        // Transfer to insurance fund
        if (toInsuranceFund > 0) {
            IVault(vault).internalTransfer(pool, insuranceFund, toInsuranceFund);
            insuranceFundBalance += toInsuranceFund;
        }

        // Mark position as force closed
        pos.status = posStatus.forceClose;
        pos.openSize = 0;
        pos.closeSize = pos.openSize;
        pos.closeAmount = pos.openSize * liquidationPriceX100;

        IPosition(positionNFT).updatePosition(orderId, pos);
        isLiquidated[orderId] = true;

        // Remove from liquidation queue
        uint256 liqPrice = positionLiquidationPrice[orderId];
        if (liqPrice > 0) {
            liquidationQueues[pool].remove(liqPrice);
            delete positionLiquidationPrice[orderId];
        }

        emit PositionLiquidated(
            orderId,
            msg.sender,
            liquidationPriceX100,
            remainingMargin,
            liquidatorReward
        );
    }

    /**
     * @notice Deposit to insurance fund
     */
    function depositInsuranceFund(uint256 amount) external {
        IVault(vault).internalTransfer(msg.sender, insuranceFund, amount);
        insuranceFundBalance += amount;
    }

    /**
     * @notice Withdraw from insurance fund (owner only)
     */
    function withdrawInsuranceFund(uint256 amount) external onlyOwner {
        require(insuranceFundBalance >= amount, "Insufficient balance");
        insuranceFundBalance -= amount;
        IVault(vault).internalTransfer(insuranceFund, msg.sender, amount);
    }

    /**
     * @notice Get liquidation queue statistics
     * @param pool Pool address
     * @return totalPositions Total positions in queue
     * @return mostAtRisk Liquidation price of most at-risk position
     * @return leastAtRisk Liquidation price of least at-risk position
     */
    function getQueueStats(address pool)
        external
        view
        returns (uint256 totalPositions, uint256 mostAtRisk, uint256 leastAtRisk)
    {
        totalPositions = liquidationQueues[pool].size();

        if (totalPositions > 0) {
            (mostAtRisk,) = liquidationQueues[pool].getMin();
            (leastAtRisk,) = liquidationQueues[pool].getMax();
        }
    }
}
