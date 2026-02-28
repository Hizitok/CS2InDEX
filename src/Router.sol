// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRouter}   from "./interfaces/IRouter.sol";
import {IFactory}  from "./interfaces/IFactory.sol";
import {IPool}     from "./interfaces/IPool.sol";
import {IVault}    from "./interfaces/IVault.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {IERC20}    from "./interfaces/IERC20.sol";
import {ReentrancyGuard} from "./libraries/ReentrancyGuard.sol";

/**
 * @title CS2InDEXRouter
 * @notice Single entry-point for all user-facing trading operations.
 *
 * Design invariants:
 *  - Router holds NO funds and NO vault balance at rest.
 *  - Positions are always owned by the user (msg.sender), not the Router.
 *  - Margin is pulled from the user's vault balance via Pool.newOrderFor().
 *
 * User prerequisites:
 *  - deposit / depositAndOpen : USDC.approve(router, amount)
 *  - close / cancel / batchClose : positionNFT.setApprovalForAll(router, true)
 *
 * Pool prerequisite (set by owner/factory after deployment):
 *  - pool.setRouter(router)
 */
contract CS2InDEXRouter is IRouter, ReentrancyGuard {

    // ── Immutables ────────────────────────────────────────────────────────────

    address public immutable override factory;
    address public immutable override vault;
    address public immutable override nft;
    address public immutable override usdc;

    // ── Errors ────────────────────────────────────────────────────────────────

    error InvalidPool();
    error ArrayMismatch();
    error ZeroAmount();

    // ── Constructor ───────────────────────────────────────────────────────────

    /**
     * @param _factory Factory address — all other addresses are derived from it.
     */
    constructor(address _factory) {
        require(_factory != address(0), "Router: zero factory");
        factory = _factory;

        address _vault = IFactory(_factory).vault();
        address _nft   = IFactory(_factory).nft();

        // Resolve USDC from Vault.supportedToken()
        (bool ok, bytes memory data) = _vault.staticcall(
            abi.encodeWithSignature("supportedToken()")
        );
        require(ok && data.length == 32, "Router: cannot resolve USDC");
        address _usdc = abi.decode(data, (address));

        vault = _vault;
        nft   = _nft;
        usdc  = _usdc;
    }

    // ── Modifiers ─────────────────────────────────────────────────────────────

    modifier validPool(address pool) {
        if (!IFactory(factory).isValidPool(pool)) revert InvalidPool();
        _;
    }

    // ── Vault Helpers ─────────────────────────────────────────────────────────

    /// @inheritdoc IRouter
    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _pullAndDeposit(msg.sender, amount);
        emit Deposited(msg.sender, amount);
    }

    /// @inheritdoc IRouter
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        // withdrawFor deducts from the user's vault balance and sends to them.
        // withdrawTo(msg.sender=Router) would incorrectly deduct from Router's
        // balance (always 0). The Router is authorized in Vault via setRouter().
        IVault(vault).withdrawFor(msg.sender, msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    // ── Core Trading ──────────────────────────────────────────────────────────

    /// @inheritdoc IRouter
    function depositAndOpen(
        address pool,
        uint256 depositAmount,
        uint256 margin,
        PoolOrder calldata order
    ) external nonReentrant validPool(pool) returns (OrderId posId) {
        if (depositAmount == 0 || margin == 0) revert ZeroAmount();
        _pullAndDeposit(msg.sender, depositAmount);
        posId = IPool(pool).newOrderFor(msg.sender, margin, order);
        emit PositionOpened(pool, msg.sender, posId);
    }

    /// @inheritdoc IRouter
    function open(
        address pool,
        uint256 margin,
        PoolOrder calldata order
    ) external nonReentrant validPool(pool) returns (OrderId posId) {
        if (margin == 0) revert ZeroAmount();
        posId = IPool(pool).newOrderFor(msg.sender, margin, order);
        emit PositionOpened(pool, msg.sender, posId);
    }

    /// @inheritdoc IRouter
    /// @dev Pool.closePosition uses isAuthorized(orderId, msg.sender=router) — needs NFT approval.
    ///      PnL settlement is triggered automatically by matchMaking and goes to ownerOf (user).
    function close(
        address pool,
        OrderId orderId,
        PoolOrder calldata closeOrder
    ) external nonReentrant validPool(pool) {
        IPool(pool).closePosition(orderId, closeOrder);
        emit PositionClosed(pool, msg.sender, orderId);
    }

    /// @inheritdoc IRouter
    /// @dev Margin refund goes to NFT owner (user), not Router, due to the fix in Pool.cancelOrder.
    function cancel(
        address pool,
        OrderId orderId
    ) external nonReentrant validPool(pool) returns (bool) {
        bool ok = IPool(pool).cancelOrder(orderId);
        emit OrderCancelled(pool, msg.sender, orderId);
        return ok;
    }

    // ── Batch Operations ──────────────────────────────────────────────────────

    /// @inheritdoc IRouter
    function batchOpen(
        address[]   calldata pools,
        uint256[]   calldata margins,
        PoolOrder[] calldata orders
    ) external nonReentrant returns (OrderId[] memory posIds) {
        uint256 n = pools.length;
        if (n != margins.length || n != orders.length) revert ArrayMismatch();

        posIds = new OrderId[](n);
        for (uint256 i = 0; i < n; i++) {
            if (!IFactory(factory).isValidPool(pools[i])) revert InvalidPool();
            if (margins[i] == 0) revert ZeroAmount();
            posIds[i] = IPool(pools[i]).newOrderFor(msg.sender, margins[i], orders[i]);
            emit PositionOpened(pools[i], msg.sender, posIds[i]);
        }
    }

    /// @inheritdoc IRouter
    function batchClose(
        address[]   calldata pools,
        OrderId[]   calldata orderIds,
        PoolOrder[] calldata closeOrders
    ) external nonReentrant {
        uint256 n = pools.length;
        if (n != orderIds.length || n != closeOrders.length) revert ArrayMismatch();

        for (uint256 i = 0; i < n; i++) {
            if (!IFactory(factory).isValidPool(pools[i])) revert InvalidPool();
            IPool(pools[i]).closePosition(orderIds[i], closeOrders[i]);
            emit PositionClosed(pools[i], msg.sender, orderIds[i]);
        }
    }

    // ── View: Portfolio ───────────────────────────────────────────────────────

    /// @inheritdoc IRouter
    function getPortfolio(address user)
        external
        view
        returns (PositionView[] memory views)
    {
        (uint256[] memory ids, Position[] memory positions) =
            IPosition(nft).getPositionsByOwner(user);

        
        views = new PositionView[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            OrderId id = OrderId.wrap(ids[i]);
            address pool = IPosition(nft).getPool(id);
            views[i] = PositionView({
                pool:        pool,
                posId:       id,
                pos:         positions[i],
                oraclePrice: IPool(pool).oraclePrice()
            });
        }
    }

    // ── View: Markets ─────────────────────────────────────────────────────────

    /// @inheritdoc IRouter
    function getAllMarkets() external view returns (MarketInfo[] memory markets) {
        address[] memory pools = IFactory(factory).getAllPools();
        markets = new MarketInfo[](pools.length);
        for (uint256 i = 0; i < pools.length; i++) {
            markets[i] = _marketInfo(pools[i]);
        }
    }

    /// @inheritdoc IRouter
    function getMarketInfo(address pool)
        external
        view
        validPool(pool)
        returns (MarketInfo memory)
    {
        return _marketInfo(pool);
    }

    /// @inheritdoc IRouter
    function getBalance(address user) external view returns (uint256) {
        return IVault(vault).balanceOf(user);
    }

    // ── Internal Helpers ──────────────────────────────────────────────────────

    /// @dev Pull USDC from user → Router → Vault.depositFor, crediting the user's vault balance.
    function _pullAndDeposit(address user, uint256 amount) internal {
        bool ok = IERC20(usdc).transferFrom(user, address(this), amount);
        require(ok, "Router: USDC pull failed");
        IERC20(usdc).approve(vault, amount);
        IVault(vault).depositFor(user, amount);
    }

    function _marketInfo(address pool) internal view returns (MarketInfo memory info) {
        (uint256 lastPrice, uint256 ask1, uint256 bid1) = IPool(pool).getOrderbookInfo();
        (string memory desc,) = IPool(pool).getPoolInfo();
        info = MarketInfo({
            pool:        pool,
            description: desc,
            lastPrice:   lastPrice,
            oraclePrice: IPool(pool).oraclePrice(),
            ask1Price:   ask1,
            bid1Price:   bid1,
            fundingIdx:  IPool(pool).fundingIdx(),
            maxLeverage: IPool(pool).maxLeverage()
        });
    }
}
