// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "./libraries/Ownable.sol";
import {IzitOSTreeMinimum} from "./libraries/IzitOSTreeMinimum.sol";
import {IEngine} from "./interfaces/IEngine.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {IOracle} from "./interfaces/IOracle.sol";

/**
 * @title Liquidation Engine
 * @notice Two-step liquidation model:
 *
 *   1. Trigger: when remaining margin <= 20% of original margin
 *   2. Action:  place a Limit closing order at the bankruptcy price
 *               (the price where margin = 0) through Pool's orderbook
 *
 *   If orderbook price is better than bankruptcy price → immediate fill
 *   Otherwise the order stays in the book waiting to be matched
 *
 * Queue ordering (both sorted ascending by triggerPx):
 *   Long queue:  getMax = most at risk, liquidate when markPrice <= triggerPx
 *   Short queue: getMin = most at risk, liquidate when markPrice >= triggerPx
 */
contract LiquidationEngine is IzitOSTreeMinimum, Ownable, IEngine {

    error InvalidPool();

    // 20% maintenance margin (2000 / 10000)
    uint256 public constant MAINTENANCE_RATE = 2000;
    uint256 public constant RATE_BASIS = 10000;

    address public factory;
    address public pool;
    address public positionNFT;
    address public oracle;

    uint256 public pxDecimals;

    // Trigger price: the price at which remaining margin = 20% of openMargin
    mapping(OrderId => uint256) public triggerPx;
    // Track position direction in the queue
    mapping(OrderId => bool) internal isShortPos;

    Tree internal longQueue;
    Tree internal shortQueue;

    modifier onlyPool() {
        if(msg.sender != pool) revert InvalidPool();
        _;
    }

    constructor(
        address _pool,
        address _positionNFT,
        address _oracle,
        uint256 _pxDecimals
    ) Ownable(msg.sender) {
        factory = msg.sender;
        pool = _pool;
        positionNFT = _positionNFT;
        oracle = _oracle;
        pxDecimals = _pxDecimals;
    }

    // -------- Comparator: sorted by trigger price -------- //

    function _less(uint256 ptrA, uint256 ptrB)
        internal
        view
        override
        returns (bool)
    {
        return triggerPx[OrderId.wrap(ptrA)] < triggerPx[OrderId.wrap(ptrB)];
    }

    // -------- Pool Integration -------- //

    /**
     * @notice Register an open position into the liquidation queue
     * @dev Called by Pool when position status becomes open
     */
    function registerPosition(OrderId oID)
        external
        onlyPool
    {
        Position memory pos = IPosition(positionNFT).getPosition(oID);
        require(pos.openSize > 0, "No open size");

        uint256 tPx = _calcTriggerPx(pos);
        triggerPx[oID] = tPx;
        isShortPos[oID] = pos.isShort;

        if (pos.isShort) {
            insert(shortQueue, OrderId.unwrap(oID));
        } else {
            insert(longQueue, OrderId.unwrap(oID));
        }

        emit PositionRegistered(oID, tPx, pos.isShort);
    }

    /**
     * @notice Remove a position from the liquidation queue
     * @dev Called by Pool when position is closed or settled
     */
    function removePosition(OrderId oID)
        external
        onlyPool
    {
        _removeFromQueue(oID);
    }

    /**
     * @notice Recalculate trigger price and re-sort in queue
     * @dev Called after funding rate update or partial close
     */
    function updatePositionInfo(OrderId oID)
        external
        onlyPool
    {
        uint256 rawId = OrderId.unwrap(oID);
        bool isShort = isShortPos[oID];

        // Remove from current position in tree
        _removeFromQueue(oID);

        // Re-evaluate
        Position memory pos = IPosition(positionNFT).getPosition(oID);
        if (pos.status != posStatus.open || pos.openSize == 0) {
            return; // position no longer open, don't re-insert
        }

        uint256 oldPx = triggerPx[oID];
        uint256 newPx = _calcTriggerPx(pos);
        triggerPx[oID] = newPx;
        isShortPos[oID] = isShort;

        if (isShort) {
            insert(shortQueue, rawId);
        } else {
            insert(longQueue, rawId);
        }

        emit TriggerPxUpdated(oID, oldPx, newPx);
    }

    // -------- Liquidation Execution -------- //

    /**
     * @notice Liquidate all positions that hit the 20% maintenance margin
     * @dev Anyone can call. For each triggered position:
     *      1. Calculate bankruptcy price (margin = 0)
     *      2. Place Limit closing order at bankruptcy price through Pool
     *      3. Normal orderbook matching takes over
     *
     *   Long:  triggered when markPrice <= triggerPx  (iterate from MAX)
     *   Short: triggered when markPrice >= triggerPx  (iterate from MIN)
     */
    function liquidate() external {
        uint256 markPrice = IOracle(oracle).oraclePrice(pool);

        // --- Long positions ---
        while (!isEmpty(longQueue)) {
            uint256 maxKey = getMax(longQueue);
            OrderId oID = OrderId.wrap(maxKey);

            if (triggerPx[oID] < markPrice) break;

            _executeLiquidation(oID, markPrice);
        }

        // --- Short positions ---
        while (!isEmpty(shortQueue)) {
            uint256 minKey = getMin(shortQueue);
            OrderId oID = OrderId.wrap(minKey);

            if (triggerPx[oID] > markPrice) break;

            _executeLiquidation(oID, markPrice);
        }
    }

    // -------- View Functions -------- //

    function getTriggerPx(OrderId oId)
        external
        view
        returns (uint256)
    {
        return triggerPx[oId];
    }

    /**
     * @notice Check if a position can be liquidated at current oracle price
     */
    function isLiquidatable(OrderId oId)
        external
        view
        returns (bool)
    {
        uint256 tPx = triggerPx[oId];
        if (tPx == 0) return false;

        uint256 markPrice = IOracle(oracle).oraclePrice(pool);

        if (isShortPos[oId]) {
            return markPrice >= tPx;
        } else {
            return markPrice <= tPx;
        }
    }

    function getQueueInfo()
        external
        view
        returns (uint256 longCount, uint256 shortCount)
    {
        longCount = longQueue.nodeCount;
        shortCount = shortQueue.nodeCount;
    }

    // -------- Internal -------- //

    /**
     * @dev Execute liquidation for a single position:
     *   1. Remove from queue
     *   2. Calculate bankruptcy price (margin = 0)
     *   3. Build a Limit closing order at bankruptcy price
     *   4. Call Pool.forceLiquidate → order enters the orderbook
     */
    function _executeLiquidation(OrderId oID, uint256 markPrice) internal {
        uint256 rawId = OrderId.unwrap(oID);
        bool isShort = isShortPos[oID];

        // 1. Remove from queue
        if (isShort) {
            remove(shortQueue, rawId);
        } else {
            remove(longQueue, rawId);
        }

        // 2. Get position and compute bankruptcy price
        Position memory pos = IPosition(positionNFT).getPosition(oID);
        uint256 bankruptPx = _calcBankruptPx(pos);

        // 3. Build closing limit order at bankruptcy price
        //    Long closes with sell, short closes with buy
        PoolOrder memory closeOrder = PoolOrder({
            isSell: !isShort,
            oType: orderType.Limit,
            size: pos.openSize,
            price: bankruptPx
        });

        // 4. Send to Pool — order enters normal matching
        IPool(pool).forceLiquidate(oID, closeOrder);

        // 5. Clean up engine state
        delete triggerPx[oID];
        delete isShortPos[oID];

        emit PositionLiquidated(oID, msg.sender, markPrice, bankruptPx);
    }

    /**
     * @dev Unified price calculation helper
     *
     *   base = openAmount - fundingDelta
     *     where fundingDelta = openFundingIdx - openSize * currentFundingIdx
     *
     *   Long:  price = (base - maxLoss * decFactor) / openSize
     *   Short: price = (base + maxLoss * decFactor) / openSize
     */
    function _calcPriceAtLoss(Position memory pos, uint256 maxLoss) internal view returns (uint256) {
        uint256 currentFundingIdx = IPool(pool).fundingIdx();
        uint256 decFactor = 10 ** pxDecimals;

        int256 fundingDelta = int256(pos.openFundingIdx)
                            - int256(pos.openSize * currentFundingIdx);

        int256 base = int256(pos.openAmount) - fundingDelta;

        int256 numerator;
        if (pos.isShort) {
            numerator = base + int256(maxLoss * decFactor);
        } else {
            numerator = base - int256(maxLoss * decFactor);
        }

        if (numerator <= 0) return 0;
        return uint256(numerator) / pos.openSize;
    }

    /**
     * @dev Trigger price: where remaining margin = 20% of openMargin
     *      maxLoss = openMargin * 80%
     */
    function _calcTriggerPx(Position memory pos) internal view returns (uint256) {
        uint256 maxLoss = pos.openMargin * (RATE_BASIS - MAINTENANCE_RATE) / RATE_BASIS;
        return _calcPriceAtLoss(pos, maxLoss);
    }

    /**
     * @dev Bankruptcy price: where remaining margin = 0
     *      maxLoss = openMargin * 100%
     */
    function _calcBankruptPx(Position memory pos) internal view returns (uint256) {
        return _calcPriceAtLoss(pos, pos.openMargin);
    }

    function _removeFromQueue(OrderId oID) internal {
        uint256 rawId = OrderId.unwrap(oID);
        bool isShort = isShortPos[oID];

        if (isShort && contains(shortQueue, rawId)) {
            remove(shortQueue, rawId);
        } else if (!isShort && contains(longQueue, rawId)) {
            remove(longQueue, rawId);
        }

        delete triggerPx[oID];
        delete isShortPos[oID];
    }
}
