// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OrderTypes} from "./OrderTypes.sol";


interface IEngine is OrderTypes {

    // Pool calls when position becomes open
    function registerPosition(OrderId oID) external;

    // Pool calls when position is closed/settled
    function removePosition(OrderId oID) external;

    // Recalculate trigger price (after funding rate update, etc.)
    function updatePositionInfo(OrderId oID) external;

    // Anyone can call to trigger liquidations
    function liquidate() external;

    // View functions
    function getTriggerPx(OrderId oId) external view returns (uint256);
    function isLiquidatable(OrderId oId) external view returns (bool);

    // Events
    event PositionRegistered(OrderId indexed oID, int256 triggerPx, bool isShort);
    event PositionLiquidated(OrderId indexed oID, address indexed liquidator, uint256 markPrice, uint256 bankruptPx);
    event TriggerPxUpdated(OrderId indexed oID, int256 oldPx, int256 newPx);
}
