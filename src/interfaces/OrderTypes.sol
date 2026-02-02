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

    enum posStatus { none, pendingOpen, open, pendingClose, forceClose, closed, settled }

    struct Position {

        uint256 positionID;

        address pool;
        bool isShort;
        posStatus status;
        // openMargin stores the margin at open price
        // funding rates are calculated in funding indexes
        uint256 openMargin;

        uint256 pendingSize;
        uint256 openSize;
        uint256 closeSize;

        // Amount = matched price * matched size
        uint256 openAmount;
        uint256 closeAmount;

        // Cumulative Funding index 
        uint256 openFundingIdx;
        uint256 closeFundingIdx;
    }

}
