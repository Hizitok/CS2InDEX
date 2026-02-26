// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPool} from "./interfaces/IPool.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IEngine} from "./interfaces/IEngine.sol";
import {Ownable} from "./libraries/Ownable.sol";
import {Pausable} from "./libraries/Pausable.sol";
import {IzitOSTreeMinimum} from "./libraries/IzitOSTreeMinimum.sol";

contract Pool is Ownable, Pausable, IPool, IzitOSTreeMinimum {

    uint256 public constant MAKERFEE = 3000;
    uint256 public constant TAKERFEE = 5000;
    uint256 public constant FEEBASIS = 1000000;

    string public description;

    address public oracle;
    address public positionNFT;
    address public vault;
    address public engine;
    address public router;

    uint256 public fundingIdx = 1 << 63;
    uint256 public lastPrice;
    uint256 public oraclePrice;
    uint256 public maxLeverage = 1000;

    // orderId => PriceX100, Size
    mapping(OrderId => uint256) internal OBPx;
    mapping(OrderId => uint256) internal OBSize;

    uint256 internal pxDecimals;
    uint256 private feeCollected;

    Tree internal _ask_OB; // Sell orders
    Tree internal _bid_OB; // Buy orders

    constructor(
        address _vault,
        address _positionNFT,
        address _oracle,
        uint256 _curDecimal,
        uint256 _initialPrice,
        string memory _description
    ) Ownable(msg.sender) {
        vault = _vault;
        positionNFT = _positionNFT;
        oracle = _oracle;
        pxDecimals = _curDecimal;
        lastPrice = _initialPrice;
        description = _description;
    }

    modifier onlyOracle() {
        if( msg.sender != oracle ) revert InvalidOracle();
        _;
    }

    modifier onlyEngine() {
        if( msg.sender != engine ) revert NotAuthorized();
        _;
    }

    modifier onlyRouter() {
        if( msg.sender != router ) revert NotAuthorized();
        _;
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

    // ------------ Emergency Pause ------------ //

    /**
     * @notice Pause new order creation (owner only)
     * @dev Cancel, close, and settle remain unaffected so users can always exit positions.
     */
    function pause() external onlyOwner { _pause(); }

    /**
     * @notice Resume new order creation (owner only)
     */
    function unpause() external onlyOwner { _unpause(); }

    /// @inheritdoc IPool
    function paused() public view override(Pausable, IPool) returns (bool) {
        return Pausable.paused();
    }

    // ------------ Interfaces Function Part ------------ //

    function newOrder(uint256 margin, PoolOrder memory pOrder)
        public
        whenNotPaused
        returns (OrderId newPosId)
    {
        return _newOrderInternal(msg.sender, margin, pOrder);
    }

    /**
     * @notice Create a new order on behalf of a trader (Router only)
     * @dev Margin is pulled from trader's vault balance; NFT is minted to trader.
     *      Only the authorized Router may call this to prevent unauthorized position creation.
     */
    function newOrderFor(address trader, uint256 margin, PoolOrder memory pOrder)
        external
        onlyRouter
        whenNotPaused
        returns (OrderId newPosId)
    {
        return _newOrderInternal(trader, margin, pOrder);
    }

    function _newOrderInternal(address trader, uint256 margin, PoolOrder memory pOrder)
        internal
        returns (OrderId newPosId)
    {
        // Basic sanity: reject zero-size and zero-margin orders
        if (pOrder.size == 0) revert InvalidOrder();
        if (margin == 0) revert InvalidOrder();

        // Price sanity check (skip for market orders)
        if (pOrder.oType != orderType.Market) {
            if (pOrder.price > lastPrice * 2) revert PxOverflow();
            if (pOrder.price < lastPrice / 2) revert PxUnderflow();
        }

        // Leverage check: position value must not exceed margin * maxLeverage.
        // For market orders, pOrder.price is 0 (price is unknown at submission), so use
        // oraclePrice as the reference price to prevent unlimited-size market orders.
        uint256 refPrice = (pOrder.oType == orderType.Market) ? oraclePrice : pOrder.price;
        if (refPrice > 0 && (pOrder.size * refPrice) / (10 ** pxDecimals) > margin * maxLeverage / 100)
            revert LeverageOverflow();

        // Transfer margin from trader's vault balance to pool
        IVault(vault).internalTransfer(trader, address(this), margin);
        // Mint position NFT to the actual trader
        newPosId = IPosition(positionNFT).newNFT(pOrder, trader, margin);

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
        uint256 refundAmount = 0;

        if ( !IPosition(positionNFT).isAuthorized(orderId, msg.sender) )
            revert NotAuthorized();
        pos = IPosition(positionNFT).getPosition(orderId);

        // delete order mapping
        delete OBSize[orderId];
        delete OBPx[orderId];

        if ( pos.status == posStatus.pendingOpen ) {

            isSellOrder = pos.isShort;
            if( pos.pendingSize == 0 ) revert InvalidStatus();

            // Save cancelled size before modifying
            uint256 cancelledSize = pos.pendingSize;

            // Only remove from tree if it was inserted (Limit/IOC orders are in tree;
            // Market orders are never inserted so skip tree removal to avoid revert).
            Tree storage ob = isSellOrder ? _ask_OB : _bid_OB;
            if (contains(ob, OrderId.unwrap(orderId))) {
                remove(ob, OrderId.unwrap(orderId));
            }
            pos.pendingSize = 0;

            // Calculate proportional refund for cancelled portion
            if ( pos.openSize == 0 ) {
                // Fully cancelled (no fills), refund all margin
                refundAmount = pos.openMargin;
            } else {
                // Partially filled, refund margin for cancelled portion only
                uint256 totalSize = pos.openSize + cancelledSize;
                refundAmount = pos.openMargin * cancelledSize / totalSize;
            }

            // Update position margin to reflect the refund
            pos.openMargin -= refundAmount;

        } else if ( pos.status == posStatus.pendingClose ) {

            isSellOrder = !pos.isShort;
            if( pos.openSize == 0 ) revert InvalidStatus();

            remove( isSellOrder ? _ask_OB : _bid_OB, OrderId.unwrap(orderId));

            // For close orders, no refund needed (margin stays with open position)
            refundAmount = 0;

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

        // Register with liquidation engine if position became open
        if (engine != address(0) && pos.status == posStatus.open) {
            IEngine(engine).registerPosition(orderId);
        }

        // Refund margin to NFT owner (not msg.sender, so Router-routed cancels work correctly)
        if (refundAmount > 0) {
            address posOwner = IPosition(positionNFT).ownerOf(OrderId.unwrap(orderId));
            IVault(vault).internalTransfer(address(this), posOwner, refundAmount);
        }

        emit OrderCancelled(orderId, msg.sender);
        cancelSuccess = true;
    }

    function closePosition(OrderId orderId, PoolOrder memory pOrder)
        external
        returns (OrderId)
    {
        // Price sanity check (skip for market orders)
        if (pOrder.oType != orderType.Market) {
            if (pOrder.price > lastPrice * 2) revert PxOverflow();
            if (pOrder.price < lastPrice / 2) revert PxUnderflow();
        }

        // Verify Authority
        if ( !IPosition(positionNFT).isAuthorized(orderId, msg.sender) ) 
            revert NotAuthorized();

        Position memory pos;
        pos = IPosition(positionNFT).getPosition(orderId);

        // Verify position is open
        if(pos.status != posStatus.open) revert InvalidStatus();

        // Verify closing direction is opposite to position direction
        // Long position (isShort=false) must close with sell (isSell=true)
        // Short position (isShort=true) must close with buy (isSell=false)
        if(pOrder.isSell == pos.isShort) revert InvalidStatus();

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
        if ( pos.isShort ) {
            // Short: profit when sell high, buy low
            // PnL = openAmount - closeAmount + funding change
            pnl = int256(pos.openAmount) - int256(pos.closeAmount);
            pnl -= int256(pos.openFundingIdx) - int256(pos.closeFundingIdx);
        } else {
            // Long: profit when buy low, sell high
            // PnL = closeAmount - openAmount + funding change
            pnl = int256(pos.closeAmount) - int256(pos.openAmount);
            pnl += int256(pos.openFundingIdx) - int256(pos.closeFundingIdx);
        }

        // Convert PnL to currency amount (divide by decimal)
        int256 pnlAmount = pnl / int256( 10**pxDecimals ) -1;

        // Calculate final return = openMargin + PnL
        uint256 finalReturn;
        if ( pnlAmount >= 0 ) {
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
        // getMin/getMax return 0 if tree is empty
        uint256 key;
        if(isSell){
            key = getMin(_ask_OB);
        } else {
            key = getMax(_bid_OB);
        }

        if (key == 0) {
            return (OrderId.wrap(0), 0, 0);
        }

        oid = OrderId.wrap(key);
        size = OBSize[oid];
        price = OBPx[oid];
    }

    // ------------ Administration Function Part ------------ //

    /**
     * @notice Update new Oracle Price
     * @param newPrice New Oracle Price
     */
    function updateOraclePrice(uint256 newPrice) external onlyOracle
    {
        oraclePrice = newPrice;
    }

    /**
     * @notice Update new Funding Index
     * @param newFundingIdx New Funding Index
     */
    function updateFundingIndex(uint256 newFundingIdx) external onlyOracle 
    {
        fundingIdx = newFundingIdx;
    }

    /**
     * @notice Set liquidation engine address (owner only)
     */
    function setEngine(address _engine) external onlyOwner {
        engine = _engine;
    }

    /**
     * @notice Set the authorized Router address (owner only)
     * @dev Only one router is active at a time. Set to address(0) to disable.
     */
    function setRouter(address _router) external onlyOwner {
        router = _router;
    }

    /**
     * @notice Force liquidate a position (engine only)
     * @dev No auth/price sanity checks. Places limit order at bankruptcy price.
     *      The order goes through normal matching — fills if price is favorable,
     *      otherwise stays in the orderbook.
     */
    function forceLiquidate(OrderId orderId, PoolOrder memory pOrder)
        external
        onlyEngine
    {
        _forceLiquidateInternal(orderId, pOrder);
    }

    /**
     * @notice Emergency close all listed positions at oracle price (owner only)
     * @dev Pauses the pool first to prevent new orders, then force-closes each
     *      position. Position IDs are supplied by an off-chain indexer (e.g. TheGraph
     *      or getPositionsByOwner). Positions that are not open are silently skipped.
     * @param positionIds Array of open position IDs to force-close
     */
    function emergencyCloseAllPositions(OrderId[] calldata positionIds)
        external
        onlyOwner
    {
        _pause();

        uint256 refPx = oraclePrice > 0 ? oraclePrice : lastPrice;

        for (uint256 i = 0; i < positionIds.length; i++) {
            OrderId oid = positionIds[i];
            Position memory pos = IPosition(positionNFT).getPosition(oid);

            // Skip positions that are not open
            if (pos.status != posStatus.open) continue;

            PoolOrder memory closeOrder = PoolOrder({
                isSell: !pos.isShort,   // long (isShort=false) → close with sell
                oType:  orderType.Limit,
                size:   pos.openSize,
                price:  refPx
            });

            // Use try/catch so a single bad position doesn't abort the batch
            try this.forceLiquidateAsOwner(oid, closeOrder) {} catch {}
        }
    }

    /**
     * @notice Self-call trampoline enabling try/catch in emergencyCloseAllPositions
     * @dev External so try works; restricted to calls from this contract only.
     */
    function forceLiquidateAsOwner(OrderId orderId, PoolOrder calldata pOrder)
        external
    {
        require(msg.sender == address(this), "Only self");
        _forceLiquidateInternal(orderId, pOrder);
    }

    function _forceLiquidateInternal(OrderId orderId, PoolOrder memory pOrder)
        internal
    {
        Position memory pos = IPosition(positionNFT).getPosition(orderId);

        if(pos.status != posStatus.open) revert InvalidStatus();
        if(pOrder.isSell == pos.isShort) revert InvalidStatus();
        if(pOrder.size > pos.openSize)
            pOrder.size = pos.openSize;

        // Mark as liquidating
        pos.status = posStatus.liquidating;
        IPosition(positionNFT).updatePosition(orderId, pos);

        // Place into orderbook and run matching
        OBPx[orderId] = pOrder.price;
        OBSize[orderId] = pOrder.size;

        orderMatching(orderId, pOrder);
    }

    /**
     * @notice Collect accumulated fees
     * @param to Address to send fees to
     */
    function collectFees(address to) external onlyOwner {
        if(feeCollected == 0) revert InvalidStatus();
        uint256 amount = feeCollected;
        feeCollected = 0;
        IVault(vault).internalTransfer(address(this), to, amount);
    }

    // ------------ Internal Function Part ------------ //

    function orderMatching(OrderId takerId, PoolOrder memory pOrder)
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

            // If orderbook is empty, stop matching
            if (OrderId.unwrap(stepId) == 0) break;

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

        // CHECK Fill or Kill Order
        if ( pOrder.oType == orderType.FOK && _size > 0) {
            revert FOK();
        }
        // CHECK Immediately or Cancelled
        if ( pOrder.oType == orderType.IOC && _size > 0) {
            cancelOrder(takerId);
        }
        // Market orders: cancel any unfilled remainder so margin is never trapped.
        // Market orders are never inserted into the tree, so cancelOrder skips tree removal.
        if ( pOrder.oType == orderType.Market && _size > 0) {
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
        // so divide 10**pxDecimals here
        matchAmt = fillSz * fillPx / 10**pxDecimals;

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

        // Register newly open positions with liquidation engine
        if (engine != address(0)) {
            if (buyPos.status == posStatus.open && buyPos.pendingSize == 0) {
                IEngine(engine).registerPosition(buyID);
            }
            if (sellPos.status == posStatus.open && sellPos.pendingSize == 0) {
                IEngine(engine).registerPosition(sellID);
            }
        }

        // Auto-settle if position is fully closed
        if ( buyPos.status == posStatus.closed && buyPos.openSize == 0) {
            if (engine != address(0)) IEngine(engine).removePosition(buyID);
            settlePnL(buyID);
        }
        if ( sellPos.status == posStatus.closed && sellPos.openSize == 0) {
            if (engine != address(0)) IEngine(engine).removePosition(sellID);
            settlePnL(sellID);
        }
        lastPrice = fillPx;

        // Notify oracle of trade for funding rate calculation
        IOracle(oracle).updatePoolInfo(fillSz, fillPx);

    }

    // Update Position information after orders matched
    function updatePosSize(Position memory pos, uint256 fillSize, uint256 fillPrice)
        private 
        view
        returns ( Position memory )
    {
        uint256 fundingChange = uint256(fillSize * fundingIdx);
        if ( pos.status == posStatus.pendingOpen ) {
            pos.pendingSize -= fillSize;
            pos.openSize += fillSize;
            pos.openAmount += fillSize * fillPrice;
            pos.openFundingIdx += fundingChange;
            if ( pos.pendingSize == 0) pos.status = posStatus.open;
        } else if ( pos.status == posStatus.pendingClose || pos.status == posStatus.liquidating)  {
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
        uint256 askMinKey = getMin(_ask_OB);
        _ask1Price = (askMinKey != 0) ? OBPx[OrderId.wrap(askMinKey)] : 0;
        uint256 bidMaxKey = getMax(_bid_OB);
        _bid1Price = (bidMaxKey != 0) ? OBPx[OrderId.wrap(bidMaxKey)] : 0;
    }

    /** NOT FINISHED
     * @notice Get Pool information

    */
    function getPoolInfo() external view
        returns (
            string memory,
            uint256
        )
    {
        // TBD
        return (description, lastPrice);
    }

    /**
     * @notice Get order book depth for depth chart display
     * @dev Traverses both order trees in price order, aggregating orders at the same
     *      price level. Asks are returned ascending (best ask first); bids descending
     *      (best bid first). Trailing entries are zero when fewer than nLevels exist.
     * @param nLevels Maximum number of distinct price levels to return per side
     * @return askPrices Sell-side price levels (ascending)
     * @return askSizes  Total open size at each ask price level
     * @return bidPrices Buy-side price levels (descending)
     * @return bidSizes  Total open size at each bid price level
     */
    function getDepth(uint256 nLevels) external view returns (
        uint256[] memory askPrices,
        uint256[] memory askSizes,
        uint256[] memory bidPrices,
        uint256[] memory bidSizes
    ) {
        askPrices = new uint256[](nLevels);
        askSizes  = new uint256[](nLevels);
        bidPrices = new uint256[](nLevels);
        bidSizes  = new uint256[](nLevels);

        // --- Asks: ascending from best ask (lowest price) ---
        uint256 key = getMin(_ask_OB);
        uint256 levelCount = 0;
        while (key != 0 && levelCount < nLevels) {
            uint256 px = OBPx[OrderId.wrap(key)];
            uint256 sz = OBSize[OrderId.wrap(key)];
            if (levelCount == 0 || askPrices[levelCount - 1] != px) {
                askPrices[levelCount] = px;
                askSizes[levelCount]  = sz;
                levelCount++;
            } else {
                askSizes[levelCount - 1] += sz;
            }
            key = nextKey(_ask_OB, key);
        }

        // --- Bids: descending from best bid (highest price) ---
        key = getMax(_bid_OB);
        levelCount = 0;
        while (key != 0 && levelCount < nLevels) {
            uint256 px = OBPx[OrderId.wrap(key)];
            uint256 sz = OBSize[OrderId.wrap(key)];
            if (levelCount == 0 || bidPrices[levelCount - 1] != px) {
                bidPrices[levelCount] = px;
                bidSizes[levelCount]  = sz;
                levelCount++;
            } else {
                bidSizes[levelCount - 1] += sz;
            }
            key = prevKey(_bid_OB, key);
        }
    }

}