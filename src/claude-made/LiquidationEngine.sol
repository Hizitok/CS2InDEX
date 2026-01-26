// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "./libraries/Ownable.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {OrderTypes} from "./interfaces/OrderTypes.sol";
import {CS2IndexOracle} from "./CS2IndexOracle.sol";

/**
 * @title LiquidationEngine
 * @notice Handles liquidation of undercollateralized positions
 */
contract LiquidationEngine is Ownable, OrderTypes {

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
     * @notice Set ADL engine address
     */
    function setADLEngine(address adl) external onlyOwner {
        // ADL engine configuration
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
     * @notice Get position health
     * @return marginRatio Margin ratio in basis points
     * @return isHealthy Whether position is above maintenance margin
     */
    function getPositionHealth(address pool, OrderId orderId)
        external
        view
        returns (uint256 marginRatio, bool isHealthy)
    {
        (bool liquidatable, uint256 ratio) = checkLiquidatable(pool, orderId);
        marginRatio = ratio;
        isHealthy = !liquidatable;
    }
}
