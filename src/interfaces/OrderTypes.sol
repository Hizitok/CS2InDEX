// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface OrderTypes {

    type OrderId is uint256;

    enum orderType {none, Market, Limit, FOK, IOC}

    struct PoolOrder {
        bool isSell; 
        orderType oType;

        uint256 size;
        uint256 price;
    }

    enum posStatus { none, pendingOpen, open, pendingClose, liquidating, closed, settled }

    struct Position {

        bool isShort;
        posStatus status;
        // openMargin stores the margin at open price
        // funding rates are calculated in funding indexes
        uint256 openMargin;

        uint128 pendingSize;
        uint128 openSize;
        uint128 closeSize;

        // Amount = matched price * matched size
        uint128 openAmount;
        uint128 closeAmount;

        // Cumulative Funding index
        uint128 openFundingIdx;
        uint128 closeFundingIdx;
    }

}
