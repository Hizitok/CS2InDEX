// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "./libraries/Ownable.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {OrderTypes} from "./interfaces/OrderTypes.sol";
import {LiquidationEngine} from "./LiquidationEngine.sol";
import {CS2IndexOracle} from "./CS2IndexOracle.sol";

/**
 * @title ADLEngine
 * @notice Auto-Deleveraging engine for closing profitable positions when insurance fund depleted
 */
contract ADLEngine is Ownable, OrderTypes {

    address public factory;
    address public vault;
    address public liquidationEngine;

    // Pool => list of open positions ranked by profitability
    mapping(address => OrderId[]) public adlQueue;

    event ADLExecuted(
        OrderId indexed orderId,
        address indexed pool,
        uint256 closePrice,
        int256 forcedPnL
    );

    constructor(address _vault) Ownable() {
        vault = _vault;
        factory = msg.sender;
    }

    /**
     * @notice Set pool authorization
     */
    function setPool(address pool, bool authorized) external onlyOwner {
        // Pool authorization logic
    }

    /**
     * @notice Set liquidation engine address
     */
    function setLiquidationEngine(address liquidation) external onlyOwner {
        liquidationEngine = liquidation;
    }

    /**
     * @notice Calculate ADL ranking score for a position
     * @dev Higher score = higher priority for ADL
     * Score = PnL% * Leverage
     */
    function calculateADLScore(
        address pool,
        OrderId orderId
    )
        public
        view
        returns (int256 score)
    {
        address positionNFT = IPool(pool).positionNFT();
        Position memory pos = IPosition(positionNFT).getPosition(orderId);

        if (pos.status != posStatus.open || pos.openSize == 0) {
            return 0;
        }

        // Get current price from oracle
        address oracle = LiquidationEngine(liquidationEngine).poolOracles(pool);
        require(oracle != address(0), "Oracle not set");
        uint256 currentPriceX100 = CS2IndexOracle(oracle).getPrice();

        // Calculate unrealized PnL
        (int256 unrealizedPnL, uint256 positionValue) =
            LiquidationEngine(liquidationEngine).calculateUnrealizedPnL(pos, currentPriceX100);

        // Only consider profitable positions for ADL
        if (unrealizedPnL <= 0) {
            return 0;
        }

        // Calculate PnL percentage
        int256 pnlPercent = (unrealizedPnL * 10000) / int256(pos.openMargin);

        // Calculate leverage = positionValue / margin
        uint256 leverage = (positionValue * 100) / pos.openMargin / 100;

        // Score = PnL% * Leverage
        score = pnlPercent * int256(leverage);
    }

    /**
     * @notice Execute ADL on profitable positions
     * @dev Called when insurance fund cannot cover liquidation losses
     * @param pool Pool address
     * @param targetAmount Total amount needed to cover deficit
     */
    function executeADL(address pool, uint256 targetAmount) external {
        require(
            msg.sender == liquidationEngine || msg.sender == owner(),
            "Only liquidation engine or owner"
        );

        address positionNFT = IPool(pool).positionNFT();
        address oracle = LiquidationEngine(liquidationEngine).poolOracles(pool);
        uint256 currentPriceX100 = CS2IndexOracle(oracle).getPrice();

        uint256 totalCollected = 0;
        uint256 maxIterations = 50; // Prevent infinite loops
        uint256 iterations = 0;

        // Build ADL queue if empty or outdated
        if (adlQueue[pool].length == 0) {
            buildADLQueue(pool);
        }

        // Execute ADL on highest ranked positions
        while (totalCollected < targetAmount && iterations < maxIterations) {
            if (adlQueue[pool].length == 0) break;

            // Get highest ranked position
            OrderId orderId = adlQueue[pool][adlQueue[pool].length - 1];
            adlQueue[pool].pop();

            Position memory pos = IPosition(positionNFT).getPosition(orderId);

            // Skip if position is not open
            if (pos.status != posStatus.open || pos.openSize == 0) {
                iterations++;
                continue;
            }

            // Calculate PnL at current price
            (int256 unrealizedPnL,) =
                LiquidationEngine(liquidationEngine).calculateUnrealizedPnL(pos, currentPriceX100);

            // Only ADL profitable positions
            if (unrealizedPnL > 0) {
                // Force close the position
                pos.status = posStatus.forceClose;
                pos.closeSize = pos.openSize;
                pos.closeAmount = pos.openSize * currentPriceX100;
                pos.openSize = 0;

                IPosition(positionNFT).updatePosition(orderId, pos);

                // Collect the profit from this position
                uint256 collectedAmount = uint256(unrealizedPnL);
                totalCollected += collectedAmount;

                emit ADLExecuted(orderId, pool, currentPriceX100, unrealizedPnL);
            }

            iterations++;
        }

        require(totalCollected >= targetAmount, "ADL insufficient");
    }

    /**
     * @notice Build ADL queue by ranking all open positions
     */
    function buildADLQueue(address pool) public {
        // Clear existing queue
        delete adlQueue[pool];

        // This is a simplified version
        // In production, you'd want to track positions more efficiently
        // For now, this function should be called periodically by a keeper
    }

    /**
     * @notice Manually add position to ADL queue
     */
    function addToADLQueue(address pool, OrderId orderId) external {
        require(msg.sender == pool || msg.sender == owner(), "Unauthorized");

        int256 score = calculateADLScore(pool, orderId);
        if (score > 0) {
            // Insert in sorted order (simple push, should be sorted properly in production)
            adlQueue[pool].push(orderId);
        }
    }

    /**
     * @notice Get ADL queue length
     */
    function getADLQueueLength(address pool) external view returns (uint256) {
        return adlQueue[pool].length;
    }

    /**
     * @notice Get ADL queue
     */
    function getADLQueue(address pool) external view returns (OrderId[] memory) {
        return adlQueue[pool];
    }
}
