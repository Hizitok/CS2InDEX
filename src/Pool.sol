// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPool} from "./interfaces/IPool.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {Ownable} from "./libraries/Ownable.sol";
import {IzitOSTreeMinimum} from "./libraries/IzitOSTreeMinimum.sol";

contract Pool is Ownable, IPool, IzitOSTreeMinimum {

    uint256 MAKERFEE = 3000;
    uint256 TAKERFEE = 5000;
    uint256 FEEBASIS = 1000000;

    string public description;

    address public factory;
    address public oracle;
    address public positionNFT;
    address public vault;

    uint128 public fundingIdx = 1 << 126;
    uint256 public lastPrice;
    uint256 public MAX_LEVERAGE = 600;

    // orderId => PriceX100, Size
    mapping(OrderId => uint256) OBPx;
    mapping(OrderId => uint256) OBSize;

    uint256 curDecimalConvert;
    uint256 feeCollected;

    Tree _ask_OB; // Sell orders
    Tree _bid_OB; // Buy orders

    constructor(
        address _vault,
        address _positionNFT,
        address _oracle,
        uint256 _curDecimal,
        uint256 _initialPrice,
        string _description
    ) Ownable(msg.sender) {
        factory = msg.sender;
        vault = _vault;
        positionNFT = _positionNFT;
        oracle = _oracle;
        curDecimalConvert = _curDecimal;
        lastPrice = _initialPrice;
        description = _description;
    }

    function _less(uint256 ptrA, uint256 ptrB)
        internal
        view
        override
        returns (bool)
    {
        // Compare Price of two orders
        return OBPx[OrderId.wrap(ptrA)] < OBPx[OrderId.wrap(ptrB)];
    }

    // ------------ Interfaces Function Part ------------ //

    function newOrder(uint256 margin, PoolOrder memory pOrder) 
        public 
        returns (OrderId newPosId) 
    {
        // Price sanity check
        if (pOrder.price <= lastPrice *2) revert PxOverflow();
        if (pOrder.price >= lastPrice /2) revert PxUnderflow();

        if (margin* MAX_LEVERAGE / 100 >= pOrder.size * pOrder.price) 
            revert LeverageOverflow();

        // Transfer margin from Vault contract to pool
        IVault(vault).internalTransfer(msg.sender, address(this), margin);
        // Then create position NFT for manage and query
        newPosId = IPosition(positionNFT).newNFT(pOrder, msg.sender);

        // update order info 
        OBPx[newPosId] = pOrder.price;
        OBSize[newPosId] = pOrder.size;

        orderMatching(newPosId, pOrder);
    }

    function cancelOrder(OrderId orderId) 
        public
        returns (bool cancelSuccess)
    {
        bool isSellOrder;
        Position memory pos;

        if ( !IPosition(positionNFT).isAuthorized(orderId, msg.sender) ) 
            revert NotAuthorized();
        pos = IPosition(positionNFT).getPosition(orderId);

        // delete order mapping
        delete OBSize[orderId];
        delete OBPx[orderId];

        if ( pos.status == posStatus.pendingOpen ) {

            isSellOrder = pos.isShort;
            if( pos.pendingSize == 0 ) revert(); 

            remove( isSellOrder ?_ask_OB:_bid_OB, OrderId.unwrap(orderId));
            pos.pendingSize = 0;

        } else if ( pos.status == posStatus.pendingClose ) {

            isSellOrder = !pos.isShort;
            if( pos.openSize == 0 ) revert(); 

            remove( isSellOrder ?_bid_OB:_ask_OB, OrderId.unwrap(orderId));

        } else {
            revert CancelFailed();
        }

        // Check status after cancel order
        if ( pos.openSize==0 ) {
            pos.status = posStatus.closed;
        } else {
            pos.status = posStatus.open;
        }

        IPosition(positionNFT).updatePosition(orderId, pos);
        cancelSuccess = true;
    }

    function closePosition(OrderId orderId, PoolOrder memory pOrder)
        external
        returns (OrderId orderId)
    {
        // Price sanity check
        if (pOrder.price <= lastPrice *2) revert PxOverflow();
        if (pOrder.price >= lastPrice /2) revert PxUnderflow();

        // Verify Authority
        if ( !IPosition(positionNFT).isAuthorized(orderId, msg.sender) ) 
            revert NotAuthorized();

        Position memory pos;
        pos = IPosition(positionNFT).getPosition(orderId);

        // Verify position is open
        if(pos.status != posStatus.open) revert InvaildStatus();

        // Verify closing direction is opposite to position direction
        // Long position (isShort=false) must close with sell (isSell=true)
        // Short position (isShort=true) must close with buy (isSell=false)
        if(pOrder.isSell == pos.isShort) revert InvaildStatus();

        // Verify closing size doesn't exceed open size
        // If exceeds, fix order size with max size
        if(pOrder.size > pos.openSize)  
            pOrder.size = pos.openSize;

        // Update position status to pendingClose
        pos.status = posStatus.pendingClose;

        // Update the position in NFT
        IPosition(positionNFT).updatePosition(orderId, pos);

        // Set up order book entries
        OBPx[orderId] = pOrder.price;
        OBSize[orderId] = pOrder.size;

        // Match the closing order
        orderMatching(orderId, pOrder);

        // Return the same orderId
        return orderId;
    }

    /**
     * @notice Settle PnL for a closed position and return funds to owner
     * @param orderId Position ID to settle
     */
    function settlePnL(OrderId orderId) 
        public 
    {
        Position memory pos = IPosition(positionNFT).getPosition(orderId);

        // CHECK Position Status
        // REQUIRE status == closed, 
        //   and have no pending Order
        if ( pos.status != posStatus.closed  ||
            pos.pendingSize != 0 ||
            pos.openSize != 0
        ) revert InvalidStatus();

        address owner = IPosition(positionNFT).ownerOf(OrderId.unwrap(orderId));

        // Calculate PnL
        // PnL = (closeAmount - openAmount) * direction
        // direction: long = +1, short = -1
        int256 pnl;
        if ( pos.isShort) {
            // Short: profit when sell high, buy low
            // PnL = openAmount - closeAmount + funding change
            pnl = int256(pos.openAmount) - int256(pos.closeAmount);
            pnl -= int256(pos.openFundingIdx - pos.closeFundingIdx);
        } else {
            // Long: profit when buy low, sell high
            // PnL = closeAmount - openAmount + funding change
            pnl = int256(pos.closeAmount) - int256(pos.openAmount);
            pnl += int256(pos.openFundingIdx - pos.closeFundingIdx);
        }

        // Convert PnL to currency amount (divide by decimal)
        int256 pnlAmount = pnl / 10**curDecimalConvert;

        // Calculate final return = openMargin + PnL
        uint256 finalReturn;
        if ( pnlAmount >= 0) {
            // Profit case
            finalReturn = pos.openMargin + uint256(pnlAmount);
        } else {
            // Loss case
            uint256 loss = uint256(-pnlAmount);
            if ( loss >= pos.openMargin) {
                // Total loss (liquidation case)
                finalReturn = 0;
            } else {
                finalReturn = pos.openMargin - loss;
            }
        }

        // Return funds to owner
        if ( finalReturn > 0) {
            IVault(vault).internalTransfer(address(this), owner, finalReturn);
        }

        // Mark position as settled in NFT contract
        IPosition(positionNFT).settlePosition(orderId);
    }


    // ------------ Self Balanced Tree Part ---------- //

    function getFirstOrder(bool isSell)
        private 
        view 
        returns (OrderId oid, uint256 size, uint256 price)
    {
        if(isSell){
            oid = OrderId.wrap(query_min( _ask_OB ));
        } else {
            oid = OrderId.wrap(query_max( _bid_OB ));
        }
        size = OBSize[oid];
        price = OBPx[oid];
    }

    // ------------ Administration Function Part ------------ //

    /**
     * @notice Update new Funding Index
     * @param newFundingIdx New Funding Index
     */
    function updateFundingIndex(uint256 newFundingIdx) external onlyOwner {
        fundingIdx = newFundingIdx;
    }

    /**
     * @notice Collect accumulated fees
     * @param to Address to send fees to
     */
    function collectFees(address to) external onlyOwner {
        if(feeCollected == 0) revert InvaildStatus();
        uint256 amount = feeCollected;
        feeCollected = 0;
        IVault(vault).internalTransfer(address(this), to, amount);
    }

    // ------------ Internal Function Part ------------ //

    function orderMatching(OrderId takerId, PoolOrder calldata pOrder)
        private
    {
        uint256 _size = pOrder.size;
        uint256 deltaSz;

        OrderId stepId;
        uint256 stepSize;
        uint256 stepPx;

        // Match with maker orders
        while (_size > 0) {
            (stepId, stepSize, stepPx) = getFirstOrder(!pOrder.isSell);
            // check If it is a better price for taker
            if (  
                pOrder.oType == orderType.Market || 
                (pOrder.isSell)? pOrder.price <= stepPx : pOrder.price >= stepPx
            ) {
                (deltaSz,,) = matchMaking( stepId, takerId, pOrder.isSell );
                _size = _size - deltaSz;
            } else {
                break;
            }
        } 

        // CHECK Fill or Kiil Order
        if ( pOrder.oType == orderType.FOK && _size > 0) {
            revert FOK();
        } 
        // CHECK Immediately or Cancelled
        if ( pOrder.oType == orderType.IOC && _size > 0) {
            cancelOrder(takerId); 
        }

        // Making new orders
        if ( pOrder.oType == orderType.Limit && _size > 0) {

            OBSize[takerId] = _size;
            OBPx[takerId] = pOrder.price;
            if ( pOrder.isSell ) {
                insert(_ask_OB, OrderId.unwrap(takerId));
            } else {
                insert(_bid_OB, OrderId.unwrap(takerId));
            }
            
        } 
    }

    // Generally, a match needs buy Px > sell Px
    // While this happens, match Px must be between sellPx and buyPx
    // while takerIsSell = true, match Px is sell Px,
    //      else match Px is buy Px
    function matchMaking(OrderId makerID, OrderId takerID, bool takerIsSell) 
        private 
        returns (uint256 fillSz, uint256 fillPx, uint256 matchAmt)
    {

        uint256 buyFee;
        uint256 sellFee;
        OrderId buyID;
        OrderId sellID;

        (buyID, sellID) = (takerIsSell) ? 
            (makerID, takerID) : (takerID, makerID);

        if(OBPx[buyID] < OBPx[sellID]) revert InvalidMatch();
        fillPx = (takerIsSell) ? OBPx[buyID] : OBPx[sellID];
    
        bool fillMaker = (OBSize[makerID] <= OBSize[takerID] );
        fillSz = (fillMaker)? OBSize[makerID] : OBSize[takerID];

        // real currency's amount need to be fixed with currency's decimal, 
        // so divide 10**curDecimalConvert here
        matchAmt = fillSz * fillPx / 10**curDecimalConvert;

        buyFee =  matchAmt * (takerIsSell ? MAKERFEE : TAKERFEE) / FEEBASIS;
        sellFee = matchAmt * (takerIsSell ? TAKERFEE : MAKERFEE) / FEEBASIS;

        Position memory buyPos;
        Position memory sellPos;

        buyPos = IPosition(positionNFT).getPosition(buyID);
        sellPos = IPosition(positionNFT).getPosition(sellID);

        buyPos.openMargin -= buyFee;
        sellPos.openMargin -= sellFee;
        feeCollected += (buyFee + sellFee);

        buyPos = updatePosSize(buyPos, fillSz, fillPx);
        sellPos = updatePosSize(sellPos, fillSz, fillPx);

        OBSize[buyID] -= fillSz;
        OBSize[sellID] -= fillSz;

        // Check maker status
        if ( takerIsSell ) {
            if ( OBSize[buyID] == 0) remove(_bid_OB, OrderId.unwrap(buyID));
        } else {
            if ( OBSize[sellID] == 0) remove(_ask_OB, OrderId.unwrap(sellID));
        }

        IPosition(positionNFT).updatePosition(buyID, buyPos);
        IPosition(positionNFT).updatePosition(sellID, sellPos);

        // Auto-settle if position is fully closed
        if ( buyPos.status == posStatus.closed && buyPos.openSize == 0) {
            settlePnL(buyID);
        }
        if ( sellPos.status == posStatus.closed && sellPos.openSize == 0) {
            settlePnL(sellID);
        }
        lastPrice = fillPx;

    }

    // Update Position information after orders matched
    function updatePosSize(Position memory pos, uint256 fillSize, uint256 fillPrice)
        private 
        returns ( Position memory )
    {
        int128 fundingChange = int128(fillSize * fundingIdx);
        if ( pos.status == posStatus.pendingOpen ) {
            pos.pendingSize -= fillSize;
            pos.openSize += fillSize;
            pos.openAmount += fillSize * fillPrice;
            pos.openFundingIdx += fundingChange;
            if ( pos.pendingSize == 0) pos.status = posStatus.open;
        } else if ( pos.status == posStatus.pendingClose )  {
            pos.openSize -= fillSize;
            pos.closeSize += fillSize;
            pos.closeAmount += fillSize * fillPrice;
            pos.closeFundingIdx += fundingChange;
            if ( pos.openSize == 0) pos.status = posStatus.closed;
        } else {
            revert InvalidStatus();
        }
        return pos;
    }

    // ------------ View Only Functions ------------ //

    /**
     * @notice Get First Order of two sides
    */
    function getFirstOrders() 
        public 
        view 
        returns (uint256 buyPrice, uint256 buySize, uint256 sellPrice, uint256 sellSize) 
    {
        (,buySize, buyPrice) = getFirstOrder(false);
        (,sellSize, sellPrice) = getFirstOrder(true);
    }

    /**
     * @notice Get Last Matched Price
    */
    function getLastPrice() public view returns (uint256) {
        return lastPrice;
    }

    /**
     * @notice Get Order Book information
    */
    function getOrderbookInfo() external view returns (
        uint256 _lastPrice,
        uint256 _ask1Price,
        uint256 _bid1Price
    ) {
        _lastPrice = lastPrice;
        uint256 askMinKey = _ask_OB.min();
        _ask1Price = (askMinKey != 0) ? OBPx[OrderId.wrap(askMinKey)] : 0;
        uint256 bidMaxKey = _bid_OB.max();
        _bid1Price = (bidMaxKey != 0) ? OBPx[OrderId.wrap(bidMaxKey)] : 0;
    }

    /** NOT FINISHED
     * @notice Get Pool information

    */
    function getPoolInfo() external view
        returns (
            string des,
            uint256 lastPrice
        ) 
    {
        // TBD
        return (description, lastPrice);
    }

}