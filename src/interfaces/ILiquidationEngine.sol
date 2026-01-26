// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OrderTypes} from "./OrderTypes.sol";

/**
 * @title ILiquidationEngine
 * @notice Interface for the Liquidation Engine
 * @dev Manages automated liquidations of undercollateralized positions
 */
interface ILiquidationEngine is OrderTypes {
    /**
     * @notice Liquidation constants
     */
    function MAINTENANCE_MARGIN() external view returns (uint256);
    function LIQUIDATION_FEE() external view returns (uint256);

    /**
     * @notice Set pool authorization
     * @param pool Pool address
     * @param authorized Authorization status
     */
    function setPool(address pool, bool authorized) external;

    /**
     * @notice Set oracle for a pool
     * @param pool Pool address
     * @param oracle Oracle address
     */
    function setPoolOracle(address pool, address oracle) external;

    /**
     * @notice Set ADL engine address
     * @param adl ADL engine address
     */
    function setADLEngine(address adl) external;

    /**
     * @notice Check if a position is liquidatable
     * @param pool Pool address
     * @param orderId Position ID
     * @return canLiquidate True if position can be liquidated
     * @return marginRatio Current margin ratio (basis points)
     */
    function checkLiquidatable(address pool, OrderId orderId)
        external
        view
        returns (bool canLiquidate, uint256 marginRatio);

    /**
     * @notice Liquidate an undercollateralized position
     * @param pool Pool address
     * @param orderId Position ID to liquidate
     */
    function liquidate(address pool, OrderId orderId) external;

    /**
     * @notice Deposit funds to insurance fund
     * @param amount Amount to deposit
     */
    function depositInsuranceFund(uint256 amount) external;

    /**
     * @notice Withdraw from insurance fund (owner only)
     * @param amount Amount to withdraw
     */
    function withdrawInsuranceFund(uint256 amount) external;

    /**
     * @notice Get insurance fund balance
     * @return Current insurance fund balance
     */
    function insuranceFundBalance() external view returns (uint256);

    /**
     * @notice Check if position has been liquidated
     * @param orderId Position ID
     * @return True if liquidated
     */
    function isLiquidated(OrderId orderId) external view returns (bool);

    /**
     * @notice Get vault address
     * @return Vault address
     */
    function vault() external view returns (address);

    /**
     * @notice Get insurance fund address
     * @return Insurance fund address
     */
    function insuranceFund() external view returns (address);

    /**
     * @notice Get ADL engine address
     * @return ADL engine address
     */
    function adlEngine() external view returns (address);

    /**
     * @notice Get oracle for a specific pool
     * @param pool Pool address
     * @return Oracle address
     */
    function poolOracles(address pool) external view returns (address);

    // Events
    event PositionLiquidated(
        OrderId indexed orderId,
        address indexed liquidator,
        uint256 liquidationFee,
        int256 pnl
    );
    event InsuranceFundUsed(OrderId indexed orderId, uint256 amount);
    event InsuranceFundDeposit(address indexed depositor, uint256 amount);
    event InsuranceFundWithdrawal(address indexed recipient, uint256 amount);
    event ADLTriggered(address indexed pool, uint256 targetAmount);
}
