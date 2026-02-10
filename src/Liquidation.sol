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
 * ── Price Derivation ──
 *
 *   Definitions (pre-multiplied values, matching Position struct):
 *     openAmount     = \Sigma(fillPrice × fillSize)            total cost basis
 *     openFundingIdx = \Sigma(fillSize × fundingIdx_at_fill)   cumulative funding
 *     openSize       = \Sigma(fillSize)                        total position size
 *     fundingIdx     = current global funding index
 *     decFactor      = 10^pxDecimals
 *
 *   PnL at closing price P (from Pool settlement):
 *     Long:  PnL = P × openSize - openAmount + openFundingIdx - openSize × fundingIdx
 *     Short: PnL = openAmount - P × openSize - openFundingIdx + openSize × fundingIdx
 *
 *   Setting PnL = -maxLoss × decFactor and solving for P:
 *     Let f(dct): f(short) = +1, f(long) = -1
 *
 *     P = (openAmount - openFundingIdx + f(dct) × maxLoss × decFactor) / openSize + fundingIdx
 *                       +─────────────── relativePx ───────────────+
 *
 *   Key insight: fundingIdx is identical across all positions, so relativePx
 *   alone determines liquidation ordering. We store relativePx in the tree
 *   and only add fundingIdx when comparing against markPrice.
 *
 *   Trigger price:    maxLoss = openMargin × 80%   → remaining margin = 20%
 *   Bankruptcy price: maxLoss = openMargin × 100%  → remaining margin = 0%
 *
 * ── Queue Ordering ──
 *
 *   Both queues sorted ascending by relativePx (actualPx = relativePx + fundingIdx):
 *     Long:  getMax = highest relativePx = most at risk
 *            liquidate while markPrice <= actualTriggerPx
 *     Short: getMin = lowest relativePx  = most at risk
 *            liquidate while markPrice >= actualTriggerPx
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
    mapping(OrderId => int256) public triggerPx;
    // Track position direction in the queue
    mapping(OrderId => bool) internal isShortPos;

    Tree internal longQueue;
    Tree internal shortQueue;

    // Active position counts (tree.nodeCount only increments, so track separately)
    uint256 public longActiveCount;
    uint256 public shortActiveCount;

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

        int256 tPx = _calcTriggerPx(pos);
        triggerPx[oID] = tPx;
        isShortPos[oID] = pos.isShort;

        if (pos.isShort) {
            insert(shortQueue, OrderId.unwrap(oID));
            shortActiveCount++;
        } else {
            insert(longQueue, OrderId.unwrap(oID));
            longActiveCount++;
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

        // Re-evaluate
        Position memory pos = IPosition(positionNFT).getPosition(oID);
        if (pos.status != posStatus.open || pos.openSize == 0) {
            return; // position no longer open, don't re-insert
        }

        int256 oldPx = triggerPx[oID];
        // Remove from current position in tree
        _removeFromQueue(oID);
        int256 newPx = _calcTriggerPx(pos);
        triggerPx[oID] = newPx;
        isShortPos[oID] = isShort;

        if (isShort) {
            insert(shortQueue, rawId);
            shortActiveCount++;
        } else {
            insert(longQueue, rawId);
            longActiveCount++;
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
        uint256 fundingIdx = IPool(pool).fundingIdx();
        // --- Long positions ---
        while (!isEmpty(longQueue)) {
            uint256 maxKey = getMax(longQueue);
            OrderId oID = OrderId.wrap(maxKey);

            if (triggerPx[oID] + int256(fundingIdx) < int256(markPrice)) break;

            _executeLiquidation(oID, markPrice, fundingIdx);
        }

        // --- Short positions ---
        while (!isEmpty(shortQueue)) {
            uint256 minKey = getMin(shortQueue);
            OrderId oID = OrderId.wrap(minKey);

            if (triggerPx[oID] + int256(fundingIdx) > int256(markPrice)) break;

            _executeLiquidation(oID, markPrice, fundingIdx);
        }
    }

    // -------- View Functions -------- //

    function getTriggerPx(OrderId oId)
        external
        view
        returns (uint256)
    {
        return uint256( triggerPx[oId] + int256(IPool(pool).fundingIdx()) );
    }

    /**
     * @notice Check if a position can be liquidated at current oracle price
     */
    function isLiquidatable(OrderId oId)
        external
        view
        returns (bool)
    {
        if (triggerPx[oId] == 0) return false;
        uint256 tPx = uint256( triggerPx[oId] + int256(IPool(pool).fundingIdx()) );

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
        longCount = longActiveCount;
        shortCount = shortActiveCount;
    }

    // -------- Internal -------- //

    /**
     * @dev Execute liquidation for a single position:
     *   1. Remove from queue
     *   2. Calculate bankruptcy price (margin = 0)
     *   3. Build a Limit closing order at bankruptcy price
     *   4. Call Pool.forceLiquidate → order enters the orderbook
     */
    function _executeLiquidation(OrderId oID, uint256 markPrice, uint256 fundingIdx) internal {
        uint256 rawId = OrderId.unwrap(oID);
        bool isShort = isShortPos[oID];

        // 1. Remove from queue
        if (isShort) {
            remove(shortQueue, rawId);
            shortActiveCount--;
        } else {
            remove(longQueue, rawId);
            longActiveCount--;
        }

        // 2. Get position and compute bankruptcy price
        Position memory pos = IPosition(positionNFT).getPosition(oID);
        uint256 bankruptPx = uint256( _calcBankruptPx(pos) + int256(fundingIdx) );

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
     * @dev Compute relativePx — the liquidation price before adding fundingIdx.
     *
     *   relativePx = (openAmount - openFundingIdx + f(dct) × maxLoss × decFactor) / openSize
     *
     *   Actual price = relativePx + fundingIdx (applied at comparison / execution time)
     */
    function _calcRelativePxAtLoss(Position memory pos, uint256 maxLoss) 
        internal 
        view 
        returns (int256) 
    {
        uint256 decFactor = 10 ** pxDecimals;

        int256 base = int256(pos.openAmount) - int256(pos.openFundingIdx);

        int256 numerator = base + int256(pos.isShort?int256(1):-1) * int256(maxLoss * decFactor);
        return numerator / int256(pos.openSize);
    }

    /**
     * @dev Trigger price: where remaining margin = 20% of openMargin
     *      maxLoss = openMargin * 80%
     */
    function _calcTriggerPx(Position memory pos) internal view returns (int256) {
        uint256 maxLoss = pos.openMargin * (RATE_BASIS - MAINTENANCE_RATE) / RATE_BASIS;
        return _calcRelativePxAtLoss(pos, maxLoss);
    }

    /**
     * @dev Bankruptcy price: where remaining margin = 0
     *      maxLoss = openMargin * 100%
     */
    function _calcBankruptPx(Position memory pos) internal view returns (int256) {
        return _calcRelativePxAtLoss(pos, pos.openMargin);
    }

    function _removeFromQueue(OrderId oID) internal {
        uint256 rawId = OrderId.unwrap(oID);
        bool isShort = isShortPos[oID];

        if (isShort && contains(shortQueue, rawId)) {
            remove(shortQueue, rawId);
            shortActiveCount--;
        } else if (!isShort && contains(longQueue, rawId)) {
            remove(longQueue, rawId);
            longActiveCount--;
        }

        delete triggerPx[oID];
        delete isShortPos[oID];
    }
}
