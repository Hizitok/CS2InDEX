// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPool} from "./interfaces/IPool.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {Ownable} from "./libraries/Ownable.sol";
import {IzitRBTree} from "./libraries/IzitRBTreeLib.sol";

contract Pool is Ownable, IPool, IzitRBTree {

    uint256 MAKERFEE = 3000;
    uint256 TAKERFEE = 5000;
    uint256 FEEBASIS = 1000000;

    address public factory;
    address public vault;
    address public CS2Oracle;
    address public positionNFT;
    address public currency;

    // orderId => PriceX100, Size
    mapping(OrderId => uint256) OBPx;
    mapping(OrderId => uint256) OBSize;

    uint256 lastPriceX100;
    uint256 oraclePriceX100;
    uint256 curDecimal;
    uint256 feeCollected;

    Tree _ask_OB; // Sell orders
    Tree _bid_OB; // Buy orders

    constructor(
        address _vault,
        address _positionNFT,
        address _currency,
        address _CS2Oracle,
        uint256 _curDecimal,
        uint256 _initialPrice
    ) Ownable() {
        vault = _vault;
        positionNFT = _positionNFT;
        currency = _currency;
        CS2Oracle = _CS2Oracle;
        curDecimal = _curDecimal;
        lastPriceX100 = _initialPrice;
        oraclePriceX100 = _initialPrice;
        factory = msg.sender;
    }

    function _less(OrderId ptrA, OrderId ptrB)
        internal
        override
        returns (bool)
    {
        if ( OBPx[ptrA] == 0 ) OBPx[ptrA] = IPosition(positionNFT).getOpenTick(ptrA);
        if ( OBPx[ptrB] == 0 ) OBPx[ptrB] = IPosition(positionNFT).getOpenTick(ptrB);
       
        return OBPx[ptrA] < OBPx[ptrB];
    }

    function newOrder(PoolOrder memory pOrder) public returns (OrderId newPosId) {

        require(pOrder.priceX100 <= lastPriceX100 *2, "Price overflow");
        require(pOrder.priceX100 >= lastPriceX100 /2, "Price underflow");

        newPosId = newPosition(msg.sender, pOrder);

        orderMatching(newPosId, pOrder);
    
    }

    function cancelOrder(OrderId orderId) 
        public

    {
        bool isSellOrder;
        Position memory pos;

        pos = IPosition(positionNFT).getPosition(orderId);

        isSellOrder = pos.isShort;

        if (pos.status == posStatus.pendingClose) {
            isSellOrder = !isSellOrder;
        }

        delete OBSize[orderId];
        delete OBPx[orderId];

        if (pos.status == posStatus.pendingOpen ) {

            tryRemove( isSellOrder ?_ask_OB:_bid_OB, orderId);

            pos.pendingSize = 0;
            if (pos.openSize==0) {
                pos.status = posStatus.closed;
            } else {
                pos.status = posStatus.open;
            }
        }

        if (pos.status == posStatus.pendingClose) {

            tryRemove( isSellOrder ?_bid_OB:_ask_OB, orderId);

            pos.pendingSize = 0;
            if (pos.openSize==0) {
                pos.status = posStatus.closed;
            } else {
                pos.status = posStatus.open;
            }
        }

        IPosition(positionNFT).updatePosition(orderId, pos);
    }

    function newPosition(address caller, PoolOrder calldata pOrder) 
        internal 
        returns (OrderId newPosId) 
    {

        require(pOrder.margin*6 >= pOrder.size * pOrder.priceX100 , "Leverage Overflow");

        IVault(vault).internalTransfer(caller, address(this), pOrder.margin);
        newPosId = IPosition(positionNFT).newNFT(pOrder, caller);

        OBPx[newPosId] = pOrder.priceX100;
        OBSize[newPosId] = pOrder.size;
    }

    function closePosition(OrderId orderId, PoolOrder memory pOrder)
        external
        returns (OrderId newPosId)
    {
        Position memory pos;
        pos = IPosition(positionNFT).getPosition(orderId);

        // Verify position is open
        require(pos.status == posStatus.open, "Position not open");

        // Verify caller owns the position
        require(IPosition(positionNFT).ownerOf(orderId) == msg.sender, "Not owner");

        // Verify closing direction is opposite to position direction
        // Long position (isShort=false) must close with sell (isSell=true)
        // Short position (isShort=true) must close with buy (isSell=false)
        require(pos.isShort != pOrder.isSell, "Invalid close direction");

        // Verify closing size doesn't exceed open size
        require(pOrder.size <= pos.openSize, "Size exceeds open position");

        // Price sanity checks
        require(pOrder.priceX100 <= lastPriceX100 * 2, "Price overflow");
        require(pOrder.priceX100 >= lastPriceX100 / 2, "Price underflow");

        // Update position status to pendingClose
        pos.status = posStatus.pendingClose;
        pos.pendingSize = pOrder.size;

        // Update the position in NFT
        IPosition(positionNFT).updatePosition(orderId, pos);

        // Set up order book entries
        OBPx[orderId] = pOrder.priceX100;
        OBSize[orderId] = pOrder.size;

        // Match the closing order
        orderMatching(orderId, pOrder);

        // Return the same orderId
        return orderId;
    }


    // ------------ Internal Function Part ------------ //

    function orderMatching(OrderId posId, PoolOrder memory pOrder)
        internal
    {

        uint256 _size = pOrder.size;
        uint256 deltaSz;

        uint256 stepId;
        uint256 stepSize;
        uint256 stepPx;
        // new order sell, match with buy orders
        // a new order starts with a pending order

        // Match with existed orders
        while (_size > 0) {
            (stepId, stepSize, stepPx) = getFirstOrder(!pOrder.isSell);
            if ( 
                pOrder.oType == orderType.Market || 
                // check If it is a better price for taker
                (pOrder.isSell)? pOrder.priceX100 <= stepPx : pOrder.priceX100 >= stepPx
            ) {
                (deltaSz,,) = matchMaking(stepId, posId, pOrder.isSell);
                _size = _size - deltaSz;
            } else {
                break;
            }
        } 

        if (pOrder.oType == orderType.FOK && _size > 0) {
            revert FOK();
        } 
        if (pOrder.oType == orderType.IOC && _size > 0) {
            cancelOrder(posId); 
        }

        // Making new orders
        if (pOrder.oType == orderType.Limit && _size > 0) {

            OBPx[posId] = pOrder.priceX100;
            if (pOrder.isSell) {
                insert(_ask_OB, posId);
            } else {
                insert(_bid_OB, posId);
            }
            
        } 
    }

    // Generally, a match needs buy Px > sell Px
    // While this happens, match Px must be between sellPx and buyPx
    // while takerIsSell = true, match Px is sell Px,
    //      else match Px is buy Px
    function matchMaking(OrderId buyID, OrderId sellID, bool takerIsSell) 
        private 
        returns (uint256 fillSz, uint256 fillPx, uint256 matchAmt)
    {
        Position memory buyPos;
        Position memory sellPos;

        buyPos = IPosition(positionNFT).getPosition(buyID);
        sellPos = IPosition(positionNFT).getPosition(sellID);

        require(OBPx[buyID] >= OBPx[sellID], "Price Dismatch");
    
        bool fillBuy = (OBSize[buyID] <= OBSize[sellID] );
        fillSz = (fillBuy)? OBSize[buyID] : OBSize[sellID];
        fillPx = (takerIsSell) ? OBPx[buyID] : OBPx[sellID];

        // px here were multiplied 100, 
        // so divide 100 here to get real amt 
        // then multiply with currency's decimal
        matchAmt = fillSz * fillPx * 10**curDecimal / 100;

        uint256 buyFee;
        uint256 sellFee;

        buyFee =  matchAmt * (takerIsSell ? MAKERFEE : TAKERFEE) / FEEBASIS;
        sellFee = matchAmt * (takerIsSell ? TAKERFEE : MAKERFEE) / FEEBASIS;

        buyPos.openMargin -= buyFee;
        sellPos.openMargin -= sellFee;
        feeCollected += (buyFee + sellFee);

        buyPos = updatePosSize(buyPos, fillSz, fillPx);
        sellPos = updatePosSize(sellPos, fillSz, fillPx);

        OBSize[buyID] -= fillSz;
        OBSize[sellID] -= fillSz;

        if ( takerIsSell ) {
            if (OBSize[buyID] == 0) remove(_bid_OB, buyID);
        } else {
            if (OBSize[sellID] == 0) remove(_ask_OB, sellID);
        }

        IPosition(positionNFT).updatePosition(buyID, buyPos);
        IPosition(positionNFT).updatePosition(sellID, sellPos);

        // Auto-settle if position is fully closed
        if (buyPos.status == posStatus.closed && buyPos.openSize == 0) {
            settlePnL(buyID);
        }
        if (sellPos.status == posStatus.closed && sellPos.openSize == 0) {
            settlePnL(sellID);
        }

        lastPriceX100 = fillPx;

    }


    function updatePosSize(Position memory pos, uint256 fillSize, uint256 fillPrice)
        private 
        pure
        returns ( Position memory )
    {

        if (pos.status == posStatus.pendingOpen) {
            pos.pendingSize -= fillSize;
            pos.openSize += fillSize;
            pos.openAmount += fillSize * fillPrice;
            if (pos.pendingSize == 0) pos.status = posStatus.open;
        } else if (pos.status == posStatus.pendingClose)  {
            pos.openSize -= fillSize;
            pos.closeSize += fillSize;
            pos.closeAmount += fillSize * fillPrice;
            if (pos.openSize == 0) pos.status = posStatus.closed;
        } else {
            revert("invalid status");
        }
        return pos;
    }

    function getFirstOrder(bool isSell) 
        public 
        view 
        returns (uint256 keyPtr, uint256 size, uint256 priceX100) 
    {
        if (isSell) {
            // get first sell order
            keyPtr = _ask_OB.min();
        } else {
            // get first buy order
            keyPtr = _bid_OB.max();
        }
        require(keyPtr != 0, "No Order");
        size = OBSize[keyPtr];
        priceX100 = OBPx[keyPtr];
    }

    function getLastPrice() public view returns (uint256) {
        return lastPriceX100;
    }

    /**
     * @notice Settle PnL for a closed position and return funds to owner
     * @param orderId Position ID to settle
     */
    function settlePnL(OrderId orderId) public {
        Position memory pos = IPosition(positionNFT).getPosition(orderId);

        require(pos.status == posStatus.closed, "Position not closed");
        require(pos.openSize == 0, "Position still has open size");
        require(pos.closeSize > 0, "No closed position to settle");

        address owner = IPosition(positionNFT).ownerOf(OrderId.unwrap(orderId));

        // Calculate PnL
        // PnL = (closeAmount - openAmount) * direction
        // direction: long = +1, short = -1
        int256 pnl;
        if (pos.isShort) {
            // Short: profit when sell high, buy low
            // PnL = openAmount - closeAmount
            pnl = int256(pos.openAmount) - int256(pos.closeAmount);
        } else {
            // Long: profit when buy low, sell high
            // PnL = closeAmount - openAmount
            pnl = int256(pos.closeAmount) - int256(pos.openAmount);
        }

        // Convert PnL to currency amount (divide by 100 and multiply by decimal)
        int256 pnlAmount = pnl * int256(10**curDecimal) / 100;

        // Calculate final return = openMargin + PnL
        uint256 finalReturn;
        if (pnlAmount >= 0) {
            // Profit case
            finalReturn = pos.openMargin + uint256(pnlAmount);
        } else {
            // Loss case
            uint256 loss = uint256(-pnlAmount);
            if (loss >= pos.openMargin) {
                // Total loss (liquidation case)
                finalReturn = 0;
            } else {
                finalReturn = pos.openMargin - loss;
            }
        }

        // Return funds to owner
        if (finalReturn > 0) {
            IVault(vault).internalTransfer(address(this), owner, finalReturn);
        }

        // Mark position as settled in NFT contract
        IPosition(positionNFT).settlePosition(orderId);
    }

    /**
     * @notice Update oracle price
     * @param newPrice New oracle price x100
     */
    function updateOraclePrice(uint256 newPrice) external onlyOwner {
        oraclePriceX100 = newPrice;
    }

    /**
     * @notice Collect accumulated fees
     * @param to Address to send fees to
     */
    function collectFees(address to) external onlyOwner {
        require(feeCollected > 0, "No fees to collect");
        uint256 amount = feeCollected;
        feeCollected = 0;
        IVault(vault).internalTransfer(address(this), to, amount);
    }

    /**
     * @notice Get pool information
     */
    function getPoolInfo() external view returns (
        uint256 _lastPriceX100,
        uint256 _oraclePriceX100,
        uint256 _feeCollected,
        uint256 _askMin,
        uint256 _bidMax
    ) {
        _lastPriceX100 = lastPriceX100;
        _oraclePriceX100 = oraclePriceX100;
        _feeCollected = feeCollected;

        uint256 askMinKey = _ask_OB.min();
        _askMin = (askMinKey != 0) ? OBPx[OrderId.wrap(askMinKey)] : 0;

        uint256 bidMaxKey = _bid_OB.max();
        _bidMax = (bidMaxKey != 0) ? OBPx[OrderId.wrap(bidMaxKey)] : 0;
    }

}