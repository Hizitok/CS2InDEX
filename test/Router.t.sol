// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {TestERC20}        from "./mocks/TestERC20.sol";
import {CS2InDEXFactory}  from "../src/Factory.sol";
import {CS2InDEXRouter}   from "../src/Router.sol";
import {Vault}            from "../src/Vault.sol";
import {Pool}             from "../src/Pool.sol";
import {positionNFT}      from "../src/PositionNFT.sol";
import {IndexOracle}      from "../src/IndexOracle.sol";
import {IRouter}          from "../src/interfaces/IRouter.sol";
import {OrderTypes}       from "../src/interfaces/OrderTypes.sol";

/**
 * @title RouterTest
 * @notice Integration tests for Router, Factory.setRouter, and Vault.withdrawFor.
 *         Uses real (non-mock) contract stack identical to the production deployment.
 *
 * Deployment order:
 *   1. TestERC20 (USDC)
 *   2. Factory  (deploys Vault, Oracle, NFT internally)
 *   3. Router   (reads vault/nft/usdc from Factory)
 *   4. factory.setRouter(router)   — authorises Router in Vault + any existing pools
 *   5. factory.createPool(...)     — new pool is automatically wired to Router
 */
contract RouterTest is Test, OrderTypes {

    // ─── Contracts ──────────────────────────────────────────────────────────
    TestERC20        public usdc;
    CS2InDEXFactory  public factory;
    CS2InDEXRouter   public router;
    Vault            public vault;
    Pool             public pool;
    positionNFT      public nft;
    IndexOracle      public oracle;

    // ─── Users ──────────────────────────────────────────────────────────────
    address public owner   = address(this);
    address public trader1 = address(0x1);
    address public trader2 = address(0x2);
    address public trader3 = address(0x3);

    // ─── Constants ──────────────────────────────────────────────────────────
    uint256 constant PX          = 100e6;   // $100 oracle / initial price
    uint256 constant PX_DEC      = 6;
    uint256 constant DEPOSIT     = 10_000e6; // $10 000 USDC
    uint256 constant MARGIN      = 200e6;    // $200 margin (5x on $100 position)
    uint256 constant SIZE        = 1e6;      // 1 contract
    string  constant ITEM        = "AK47-Redline";

    // ─── Setup ──────────────────────────────────────────────────────────────

    function setUp() public {
        // 1. USDC
        usdc = new TestERC20("USD Coin", "USDC", 6);

        // 2. Factory
        factory = new CS2InDEXFactory(address(usdc));
        vault   = Vault(factory.vault());
        oracle  = IndexOracle(factory.oracle());
        nft     = positionNFT(factory.nft());

        // 3. Router
        router = new CS2InDEXRouter(address(factory));

        // 4. Register Router: authorises in Vault + wires to existing pools
        factory.setRouter(address(router));

        // 5. Create pool (auto-wires router)
        (address poolAddr,) = factory.createPool(ITEM, PX, PX_DEC);
        pool = Pool(poolAddr);

        // 6. Feed oracle price so pool.oraclePrice is set
        factory.updatePrice(address(pool), PX);

        // 7. Mint USDC and approve router
        _setupTrader(trader1, 100_000e6);
        _setupTrader(trader2, 100_000e6);
        _setupTrader(trader3, 100_000e6);
    }

    /// @dev Mint USDC and approve both Vault and Router for a trader
    function _setupTrader(address user, uint256 amount) internal {
        usdc.mint(user, amount);
        vm.prank(user);
        usdc.approve(address(router), type(uint256).max);
        vm.prank(user);
        usdc.approve(address(vault), type(uint256).max);
        // Approve router to act on NFT positions (needed for close/cancel)
        vm.prank(user);
        nft.setApprovalForAll(address(router), true);
    }

    // ════════════════════════════════════════════════════════════════════════
    //                        FACTORY — setRouter
    // ════════════════════════════════════════════════════════════════════════

    function testFactory_RouterStored() public view {
        assertEq(factory.router(), address(router), "Factory should store router");
    }

    function testFactory_SetRouter_AuthorisesInVault() public view {
        assertTrue(vault.isPoolAuthorized(address(router)), "Router should be authorised in Vault");
    }

    function testFactory_SetRouter_WiresExistingPool() public view {
        assertEq(pool.router(), address(router), "Pool.router should point to Router");
    }

    /// @dev Creating a pool AFTER setRouter still wires the router automatically
    function testFactory_CreatePool_AutowiresRouter() public {
        (address pool2Addr,) = factory.createPool("AWP-Dragon", 200e6, PX_DEC);
        assertEq(Pool(pool2Addr).router(), address(router), "New pool should be autowired");
    }

    function testFactory_SetRouter_RevertZeroAddress() public {
        vm.expectRevert("Factory: zero router");
        factory.setRouter(address(0));
    }

    function testFactory_SetRouter_RevertNotOwner() public {
        vm.prank(trader1);
        vm.expectRevert();
        factory.setRouter(address(0xBEEF));
    }

    /// @dev Replacing the router deauthorises the old one and authorises the new one
    function testFactory_SetRouter_Replacement() public {
        CS2InDEXRouter router2 = new CS2InDEXRouter(address(factory));
        factory.setRouter(address(router2));

        assertFalse(vault.isPoolAuthorized(address(router)),  "Old router should be deauthorised");
        assertTrue(vault.isPoolAuthorized(address(router2)), "New router should be authorised");
        assertEq(pool.router(), address(router2), "Pool should point to new router");
    }

    // ════════════════════════════════════════════════════════════════════════
    //                        ROUTER — Immutables
    // ════════════════════════════════════════════════════════════════════════

    function testRouter_Immutables() public view {
        assertEq(router.factory(), address(factory), "factory()");
        assertEq(router.vault(),   address(vault),   "vault()");
        assertEq(router.nft(),     address(nft),     "nft()");
        assertEq(router.usdc(),    address(usdc),    "usdc()");
    }

    // ════════════════════════════════════════════════════════════════════════
    //                        ROUTER — deposit / withdraw
    // ════════════════════════════════════════════════════════════════════════

    function testRouter_Deposit() public {
        vm.prank(trader1);
        router.deposit(DEPOSIT);

        assertEq(vault.balanceOf(trader1), DEPOSIT, "Vault balance should equal deposit");
        assertEq(usdc.balanceOf(address(vault)), DEPOSIT, "USDC should be in Vault");
    }

    function testRouter_Deposit_RevertZeroAmount() public {
        vm.prank(trader1);
        vm.expectRevert();
        router.deposit(0);
    }

    function testRouter_Withdraw() public {
        // First deposit via router
        vm.prank(trader1);
        router.deposit(DEPOSIT);

        uint256 before = usdc.balanceOf(trader1);

        vm.prank(trader1);
        router.withdraw(DEPOSIT);

        assertEq(vault.balanceOf(trader1), 0, "Vault balance should be zero after withdrawal");
        assertEq(usdc.balanceOf(trader1), before + DEPOSIT, "USDC returned to trader");
    }

    function testRouter_Withdraw_RevertInsufficientBalance() public {
        vm.prank(trader1);
        vm.expectRevert();
        router.withdraw(1e6); // nothing deposited
    }

    function testRouter_GetBalance() public {
        vm.prank(trader1);
        router.deposit(DEPOSIT);
        assertEq(router.getBalance(trader1), DEPOSIT);
    }

    // ════════════════════════════════════════════════════════════════════════
    //                        ROUTER — open / cancel
    // ════════════════════════════════════════════════════════════════════════

    function testRouter_DepositAndOpen() public {
        vm.prank(trader1);
        OrderId posId = router.depositAndOpen(
            address(pool),
            DEPOSIT,    // deposit amount
            MARGIN,     // margin used from vault
            PoolOrder({ isSell: false, oType: orderType.Limit, size: SIZE, price: PX - 1e6 })
        );

        assertTrue(OrderId.unwrap(posId) != 0, "posId should be non-zero");
        // NFT minted to actual trader, not router
        assertEq(nft.ownerOf(OrderId.unwrap(posId)), trader1, "NFT owner should be trader1");
        // USDC deposited into vault
        assertEq(usdc.balanceOf(address(vault)), DEPOSIT, "USDC should be in vault");
        // Vault balance: deposit minus margin
        assertEq(vault.balanceOf(trader1), DEPOSIT - MARGIN, "Remaining vault balance");
    }

    function testRouter_Open() public {
        // Pre-fund via vault directly
        vm.prank(trader1);
        vault.deposit(DEPOSIT);

        vm.prank(trader1);
        OrderId posId = router.open(
            address(pool),
            MARGIN,
            PoolOrder({ isSell: false, oType: orderType.Limit, size: SIZE, price: PX - 1e6 })
        );

        assertTrue(OrderId.unwrap(posId) != 0, "posId non-zero");
        assertEq(nft.ownerOf(OrderId.unwrap(posId)), trader1, "NFT owner");
    }

    function testRouter_Open_RevertInvalidPool() public {
        vm.prank(trader1);
        vault.deposit(DEPOSIT);

        vm.prank(trader1);
        vm.expectRevert();
        router.open(
            address(0xDEAD), // not a valid pool
            MARGIN,
            PoolOrder({ isSell: false, oType: orderType.Limit, size: SIZE, price: PX - 1e6 })
        );
    }

    function testRouter_Cancel() public {
        // Deposit and open pending limit order (price far from current, so no fill)
        vm.prank(trader1);
        vault.deposit(DEPOSIT);

        vm.prank(trader1);
        OrderId posId = router.open(
            address(pool),
            MARGIN,
            PoolOrder({ isSell: false, oType: orderType.Limit, size: SIZE, price: PX / 2 })
        );

        uint256 balBefore = vault.balanceOf(trader1);

        // Cancel via router (router is approvedForAll by trader1)
        vm.prank(trader1);
        bool ok = router.cancel(address(pool), posId);

        assertTrue(ok, "cancel should succeed");
        // Margin refunded to trader
        assertGt(vault.balanceOf(trader1), balBefore, "Margin should be refunded on cancel");
    }

    // ════════════════════════════════════════════════════════════════════════
    //                        ROUTER — close (matched position)
    // ════════════════════════════════════════════════════════════════════════

    /// @dev Open a matched long/short pair so both positions are status=open
    function _openMatchedPositions()
        internal
        returns (OrderId longId, OrderId shortId)
    {
        vm.prank(trader1);
        vault.deposit(DEPOSIT);
        vm.prank(trader2);
        vault.deposit(DEPOSIT);

        // Trader1 limit buy at exactly PX
        vm.prank(trader1);
        longId = router.open(
            address(pool),
            MARGIN,
            PoolOrder({ isSell: false, oType: orderType.Limit, size: SIZE, price: PX })
        );

        // Trader2 limit sell at PX → matches immediately
        vm.prank(trader2);
        shortId = router.open(
            address(pool),
            MARGIN,
            PoolOrder({ isSell: true, oType: orderType.Limit, size: SIZE, price: PX })
        );
    }

    function testRouter_Close() public {
        (OrderId longId, OrderId shortId) = _openMatchedPositions();

        // Trader2 must provide a buy-side counter-order for trader1 to close against
        vm.prank(trader3);
        vault.deposit(DEPOSIT);
        vm.prank(trader3);
        router.open(
            address(pool),
            MARGIN,
            PoolOrder({ isSell: false, oType: orderType.Limit, size: SIZE, price: PX })
        );

        // Trader1 closes the long via router
        vm.prank(trader1);
        router.close(
            address(pool),
            longId,
            PoolOrder({ isSell: true, oType: orderType.Limit, size: SIZE, price: PX })
        );

        Position memory pos = nft.getPosition(longId);
        assertTrue(
            pos.status == posStatus.closed || pos.status == posStatus.settled,
            "Long position should be closed/settled"
        );

        // shortId still open (trader2 did not close it yet)
        Position memory spos = nft.getPosition(shortId);
        assertTrue(spos.status == posStatus.open, "Short position still open");
    }

    // ════════════════════════════════════════════════════════════════════════
    //                        ROUTER — batch operations
    // ════════════════════════════════════════════════════════════════════════

    function testRouter_BatchOpen() public {
        vm.prank(trader1);
        vault.deposit(DEPOSIT);

        // Two pools needed for a meaningful batch; use the same pool twice for simplicity
        address[] memory pools   = new address[](2);
        uint256[] memory margins = new uint256[](2);
        PoolOrder[] memory orders = new PoolOrder[](2);

        pools[0]   = address(pool);
        pools[1]   = address(pool);
        margins[0] = MARGIN;
        margins[1] = MARGIN;
        orders[0]  = PoolOrder({ isSell: false, oType: orderType.Limit, size: SIZE, price: PX - 10e6 });
        orders[1]  = PoolOrder({ isSell: true,  oType: orderType.Limit, size: SIZE, price: PX + 10e6 });

        vm.prank(trader1);
        OrderId[] memory posIds = router.batchOpen(pools, margins, orders);

        assertEq(posIds.length, 2, "Should create 2 positions");
        assertTrue(OrderId.unwrap(posIds[0]) != 0, "posId[0] non-zero");
        assertTrue(OrderId.unwrap(posIds[1]) != 0, "posId[1] non-zero");
    }

    function testRouter_BatchOpen_RevertArrayMismatch() public {
        vm.prank(trader1);
        vault.deposit(DEPOSIT);

        address[] memory pools   = new address[](2);
        uint256[] memory margins = new uint256[](1); // mismatched
        PoolOrder[] memory orders = new PoolOrder[](2);

        vm.prank(trader1);
        vm.expectRevert();
        router.batchOpen(pools, margins, orders);
    }

    function testRouter_BatchClose() public {
        // Open two matched positions for trader1 (long) matched with trader2 (short)
        (OrderId longId,) = _openMatchedPositions();

        // Open a second matched pair for a second long position for trader1
        vm.prank(trader1);
        vault.deposit(DEPOSIT); // extra margin for second position
        vm.prank(trader2);
        vault.deposit(DEPOSIT);

        vm.prank(trader1);
        OrderId longId2 = router.open(address(pool), MARGIN,
            PoolOrder({ isSell: false, oType: orderType.Limit, size: SIZE, price: PX }));

        vm.prank(trader2);
        router.open(address(pool), MARGIN,
            PoolOrder({ isSell: true, oType: orderType.Limit, size: SIZE, price: PX }));

        // Provide counter-parties (two buys) for trader1 to close both longs
        vm.prank(trader3);
        vault.deposit(DEPOSIT * 2);
        vm.prank(trader3);
        router.open(address(pool), MARGIN,
            PoolOrder({ isSell: false, oType: orderType.Limit, size: SIZE, price: PX }));
        vm.prank(trader3);
        router.open(address(pool), MARGIN,
            PoolOrder({ isSell: false, oType: orderType.Limit, size: SIZE, price: PX }));

        // trader1 batch-closes both their long positions
        address[]   memory bPools  = new address[](2);
        OrderId[]   memory bIds    = new OrderId[](2);
        PoolOrder[] memory bOrders = new PoolOrder[](2);

        bPools[0] = address(pool);   bPools[1] = address(pool);
        bIds[0]   = longId;          bIds[1]   = longId2;
        bOrders[0] = PoolOrder({ isSell: true, oType: orderType.Limit, size: SIZE, price: PX });
        bOrders[1] = PoolOrder({ isSell: true, oType: orderType.Limit, size: SIZE, price: PX });

        vm.prank(trader1);
        router.batchClose(bPools, bIds, bOrders);

        Position memory lp1 = nft.getPosition(longId);
        Position memory lp2 = nft.getPosition(longId2);
        assertTrue(lp1.status == posStatus.closed || lp1.status == posStatus.settled, "longId should be closed");
        assertTrue(lp2.status == posStatus.closed || lp2.status == posStatus.settled, "longId2 should be closed");
    }

    // ════════════════════════════════════════════════════════════════════════
    //                        ROUTER — view functions
    // ════════════════════════════════════════════════════════════════════════

    function testRouter_GetAllMarkets() public view {
        IRouter.MarketInfo[] memory markets = router.getAllMarkets();
        assertEq(markets.length, 1, "One pool deployed");
        assertEq(markets[0].pool, address(pool));
        assertEq(markets[0].maxLeverage, 1000, "10x max leverage");
    }

    function testRouter_GetMarketInfo() public view {
        IRouter.MarketInfo memory info = router.getMarketInfo(address(pool));
        assertEq(info.pool, address(pool));
        assertEq(info.oraclePrice, PX);
    }

    function testRouter_GetMarketInfo_RevertInvalidPool() public {
        vm.expectRevert();
        router.getMarketInfo(address(0xDEAD));
    }

    function testRouter_GetPortfolio() public {
        vm.prank(trader1);
        vault.deposit(DEPOSIT);

        vm.prank(trader1);
        router.open(address(pool), MARGIN,
            PoolOrder({ isSell: false, oType: orderType.Limit, size: SIZE, price: PX - 10e6 }));

        IRouter.PositionView[] memory views = router.getPortfolio(trader1);
        assertEq(views.length, 1, "Portfolio should have one position");
        assertEq(views[0].pool, address(pool));
    }

    // ════════════════════════════════════════════════════════════════════════
    //                        VAULT — withdrawFor
    // ════════════════════════════════════════════════════════════════════════

    function testVault_WithdrawFor_AuthorisedCaller() public {
        // Fund trader1's vault balance directly
        vm.prank(trader1);
        vault.deposit(DEPOSIT);

        uint256 before = usdc.balanceOf(trader1);

        // Router (authorised pool in vault) calls withdrawFor
        vm.prank(address(router));
        vault.withdrawFor(trader1, trader1, DEPOSIT);

        assertEq(vault.balanceOf(trader1), 0, "Vault balance drained");
        assertEq(usdc.balanceOf(trader1), before + DEPOSIT, "USDC returned");
    }

    function testVault_WithdrawFor_RevertUnauthorised() public {
        vm.prank(trader1);
        vault.deposit(DEPOSIT);

        vm.prank(trader1); // trader1 is NOT an authorised pool
        vm.expectRevert("Only authorized pool");
        vault.withdrawFor(trader1, trader1, DEPOSIT);
    }

    function testVault_WithdrawFor_RevertInsufficientBalance() public {
        vm.prank(address(router)); // authorised caller
        vm.expectRevert();
        vault.withdrawFor(trader1, trader1, 1e6); // trader1 has zero balance
    }
}
