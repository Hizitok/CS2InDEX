// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ============================================================
//  CS2InDEX 一键部署合约（Remix 专用）
//
//  使用方法：
//  1. 在 Remix 打开此文件，编译（Solidity 0.8.20，开 Optimizer 200）
//  2. 选择 Injected Provider（MetaMask）或 Remix VM
//  3. 填入构造函数参数后点 Deploy：
//     - _usdc: 测试网填 0x0000...0000（自动部署 MockUSDC）
//              主网填真实 USDC 地址
//  4. 部署完成后展开合约，点各 public 变量读取地址
// ============================================================

import {CS2InDEXFactory} from "../src/Factory.sol";
import {CS2InDEXRouter}  from "../src/Router.sol";
import {IPool}           from "../src/interfaces/IPool.sol";
import {TestERC20}       from "../test/mocks/TestERC20.sol";

contract CS2InDEXDeployer {

    // ── 部署结果（全部 public，Remix 可直接点击读取）──────────────────────────

    address public usdc;
    address public factory;
    address public vault;
    address public oracle;
    address public nft;
    address public router;

    // pools[i] / engines[i] 对应下方 POOL_NAMES[i]
    address[4] public pools;
    address[4] public engines;

    string[4] public POOL_NAMES = [
        "CS2-Global-Index",
        "CS2-Knives-Index",
        "CS2-Rifles-Index",
        "CS2-Gloves-Index"
    ];

    // 测试网初始价格（$100/unit，6 位小数）
    uint256[4] internal INITIAL_PRICES = [
        uint256(100e6),
        uint256(100e6),
        uint256(100e6),
        uint256(100e6)
    ];

    uint256 constant PX_DECIMALS = 6;

    // ── 事件：方便在 Remix Logs 里看部署进度 ────────────────────────────────
    event Deployed(string step, address addr);

    // ── 构造函数：一次性完成所有部署和权限配置 ───────────────────────────────
    /**
     * @param _usdc USDC 合约地址。
     *              传 address(0) → 自动部署 MockUSDC（测试网用）
     *              传真实地址   → 使用现有 USDC（主网用）
     * @param _mintAmount 测试网 MockUSDC 给部署者 mint 的数量（6位小数，如 1000000e6 = 100万USDC）
     *                    _usdc 非零时此参数忽略
     */
    constructor(address _usdc, uint256 _mintAmount) {

        // ── Step 1: USDC ─────────────────────────────────────────────────────
        if (_usdc == address(0)) {
            TestERC20 mock = new TestERC20("USD Coin", "USDC", 6);
            uint256 amount = _mintAmount == 0 ? 1_000_000e6 : _mintAmount;
            mock.mint(msg.sender, amount);
            usdc = address(mock);
        } else {
            usdc = _usdc;
        }
        emit Deployed("MockUSDC / USDC", usdc);

        // ── Step 2: Factory（自动部署 Vault / Oracle / PositionNFT）──────────
        CS2InDEXFactory fac = new CS2InDEXFactory(usdc);
        factory = address(fac);
        vault   = fac.vault();
        oracle  = fac.oracle();
        nft     = fac.nft();
        emit Deployed("Factory", factory);
        emit Deployed("Vault",   vault);
        emit Deployed("Oracle",  oracle);
        emit Deployed("NFT",     nft);

        // ── Step 3: 创建 4 个 Pool ───────────────────────────────────────────
        for (uint256 i = 0; i < 4; i++) {
            (address pool, address engine) = fac.createPool(
                POOL_NAMES[i],
                INITIAL_PRICES[i],
                PX_DECIMALS
            );
            pools[i]   = pool;
            engines[i] = engine;
            emit Deployed(POOL_NAMES[i], pool);
        }

        // ── Step 4: 部署 Router ──────────────────────────────────────────────
        CS2InDEXRouter rtr = new CS2InDEXRouter(factory);
        router = address(rtr);
        emit Deployed("Router", router);

        // ── Step 5: 注册 Router（同时授权 Vault.withdrawFor）────────────────
        // 必须用 fac.setRouter()：Factory.setRouter() 额外执行 Vault.setPool(router, true)
        // 使 Router 可调用 Vault.withdrawFor()（用户提现路径）
        fac.setRouter(router);

        // ── Step 6: 更新初始 Oracle 价格 ────────────────────────────────────
        for (uint256 i = 0; i < 4; i++) {
            fac.updatePrice(pools[i], INITIAL_PRICES[i]);
        }
    }

    // ── 便捷 View：一次返回所有关键地址 ─────────────────────────────────────
    function getAllAddresses() external view returns (
        address _usdc,
        address _factory,
        address _vault,
        address _oracle,
        address _nft,
        address _router,
        address[4] memory _pools,
        address[4] memory _engines
    ) {
        return (usdc, factory, vault, oracle, nft, router, pools, engines);
    }

    // ── 便捷 View：返回某个 Pool 的完整信息 ──────────────────────────────────
    function getPoolInfo(uint256 index) external view returns (
        string memory name,
        address pool,
        address engine,
        uint256 lastPrice,
        uint256 oraclePrice_
    ) {
        require(index < 4, "index out of range");
        name        = POOL_NAMES[index];
        pool        = pools[index];
        engine      = engines[index];
        lastPrice   = IPool(pool).getLastPrice();
        oraclePrice_ = IPool(pool).oraclePrice();
    }
}
