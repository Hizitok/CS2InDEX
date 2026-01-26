// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface OrderTypes {

    enum posStatus { none, pendingOpen, open, pendingClose, forceClose, closed }

    struct Position {

        address pool;
        uint256 positionID;

        posStatus status;
        bool isShort; //  0 for long position, 1 for short

        // openMargin stores the margin at open price
        uint256 openMargin;

        uint256 pendingSize;
        uint256 openSize;
        uint256 closeSize;

        // Amount = matched price * size
        // by the way, closeMargin = openMargin + dct * (openAmount - closeAmount) 
        // dct = (isShort) ? -1 : 1;
        uint256 openAmount;
        uint256 closeAmount;
    }

    type OrderId is uint256;

    enum orderType {Market, Limit, FOK, IOC}

    struct PoolOrder {

        bool isSell; // 0 for sell order, 1 for buy order
        orderType oType;

        uint256 size;
        uint256 priceX100;

        uint256 margin;
    }


}
