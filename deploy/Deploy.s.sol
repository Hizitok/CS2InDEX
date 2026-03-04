// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";

import {CS2InDEXFactory} from "../src/Factory.sol";
import {CS2InDEXRouter}  from "../src/Router.sol";
import {IPool}           from "../src/interfaces/IPool.sol";
import {TestERC20}       from "../test/mocks/TestERC20.sol";

/**
 * @title CS2InDEX 一键部署脚本
 *
 * 用法（测试网，自动 mint MockUSDC）：
 *   forge script deploy/Deploy.s.sol --rpc-url sepolia --broadcast --verify -vvvv
 *
 * 用法（主网，使用真实 USDC）：
 *   USDC_ADDRESS=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 \
 *   forge script deploy/Deploy.s.sol --rpc-url mainnet --broadcast --verify --slow -vvvv
 *
 * 环境变量（写在 .env 里）：
 *   PRIVATE_KEY       部署者私钥
 *   USDC_ADDRESS      主网填真实 USDC，测试网留空则自动部署 MockUSDC
 *   DEPLOYER_MINT     测试网给部署者 mint 的 USDC 数量（默认 1,000,000 USDC）
 */
contract Deploy is Script {
    using stdJson for string;

    // ╔══════════════════════════════════════════════════════════════════╗
    // ║                    POOL CONFIGURATION                           ║
    // ║  编辑 deploy/pools.config.json 来增删改 Pool，无需改动 Solidity  ║
    // ║  格式：[{ "initialPrice": 393500000, "name": "...", "pxDecimals": 6 }]║
    // ║  价格 raw = 实际价格 × 10^pxDecimals  例：$393.5 × 10^6         ║
    // ╚══════════════════════════════════════════════════════════════════╝

    // For stdJson ABI decoding: fields must be in alphabetical order of JSON keys
    struct PoolConfigJson {
        uint256 initialPrice; // 'i' < 'n' < 'p'  ← alphabetical order required
        string  name;
        uint256 pxDecimals;
    }

    struct PoolConfig {
        string  name;
        uint256 initialPrice; // raw price = actual price × 10^pxDecimals
        uint256 pxDecimals;
    }

    PoolConfig[] internal POOLS;

    function setUp() public {
        // ── 从 deploy/pools.config.json 读取 Pool 配置 ────────────────
        string memory json = vm.readFile("deploy/pools.config.json");
        bytes memory raw = vm.parseJson(json, "$");
        PoolConfigJson[] memory decoded = abi.decode(raw, (PoolConfigJson[]));
        for (uint256 i = 0; i < decoded.length; i++) {
            POOLS.push(PoolConfig(decoded[i].name, decoded[i].initialPrice, decoded[i].pxDecimals));
        }
        // ──────────────────────────────────────────────────────────────
    }

    // ── 部署结果（供脚本内引用）──────────────────────────────────────────────

    address public usdc;
    address public factory;
    address public vault;
    address public oracle;
    address public nft;
    address public router;

    address[] public pools;
    address[] public engines;

    // ── 主流程 ────────────────────────────────────────────────────────────────

    function run() external {
        uint256 deployerKey  = vm.envUint("PRIVATE_KEY");
        address deployer     = vm.addr(deployerKey);

        // 测试网：留空则部署 MockUSDC；主网：填入真实 USDC 地址
        address usdcEnv = vm.envOr("USDC_ADDRESS", address(0));

        vm.startBroadcast(deployerKey);

        // ── Step 1: USDC ──────────────────────────────────────────────────────
        if (usdcEnv == address(0)) {
            // 测试网：部署 MockUSDC 并给部署者 mint
            TestERC20 mock = new TestERC20("Mock USDC", "USDC", 6);
            uint256 mintAmount = vm.envOr("DEPLOYER_MINT", uint256(1_000_000e6));
            mock.mint(deployer, mintAmount);
            usdc = address(mock);
            console.log("[MockUSDC]  deployed:", usdc);
            console.log("           minted %s USDC to deployer", mintAmount / 1e6);
        } else {
            usdc = usdcEnv;
            console.log("[USDC]      using existing:", usdc);
        }

        // ── Step 2: Factory（自动部署 Vault / Oracle / PositionNFT）───────────
        CS2InDEXFactory fac = new CS2InDEXFactory(usdc);
        factory = address(fac);
        vault   = fac.vault();
        oracle  = fac.oracle();
        nft     = fac.nft();

        console.log("[Factory]   deployed:", factory);
        console.log("[Vault]     deployed:", vault);
        console.log("[Oracle]    deployed:", oracle);
        console.log("[NFT]       deployed:", nft);

        // ── Step 3: 创建各 Pool ────────────────────────────────────────────────
        for (uint256 i = 0; i < POOLS.length; i++) {
            (address pool, address engine) = fac.createPool(
                POOLS[i].name,
                POOLS[i].initialPrice,
                POOLS[i].pxDecimals
            );
            pools.push(pool);
            engines.push(engine);
            console.log("[Pool]     ", POOLS[i].name);
            console.log("            pool  :", pool);
            console.log("            engine:", engine);
        }

        // ── Step 4: 部署 Router ────────────────────────────────────────────────
        CS2InDEXRouter rtr = new CS2InDEXRouter(factory);
        router = address(rtr);
        console.log("[Router]    deployed:", router);

        // ── Step 5: 注册 Router（同时授权 Vault.withdrawFor）────────────────────
        // 必须用 fac.setRouter()，而非直接调 IPool.setRouter()：
        //   Factory.setRouter() 额外执行 Vault.setPool(router, true)
        //   使 Router 可调用 Vault.withdrawFor()（用户提现路径）
        fac.setRouter(router);
        console.log("[Router]    wired to all pools + authorized in Vault");

        // ── Step 6: 更新初始 Oracle 价格 ──────────────────────────────────────
        // Factory 是 Oracle 的 owner，通过 factory.updatePrice 中继
        for (uint256 i = 0; i < pools.length; i++) {
            fac.updatePrice(pools[i], POOLS[i].initialPrice);
        }
        console.log("[Oracle]    initial prices set");

        vm.stopBroadcast();

        // ── Step 7: 输出 JSON，写入文件 ────────────────────────────────────────
        _writeDeployment();
    }

    // ── 输出部署结果到 JSON ───────────────────────────────────────────────────

    function _writeDeployment() internal {
        string memory json = "{";

        json = string.concat(json, '"usdc":"',    vm.toString(usdc),    '",');
        json = string.concat(json, '"factory":"', vm.toString(factory), '",');
        json = string.concat(json, '"vault":"',   vm.toString(vault),   '",');
        json = string.concat(json, '"oracle":"',  vm.toString(oracle),  '",');
        json = string.concat(json, '"nft":"',     vm.toString(nft),     '",');
        json = string.concat(json, '"router":"',  vm.toString(router),  '",');

        json = string.concat(json, '"pools":[');
        for (uint256 i = 0; i < pools.length; i++) {
            json = string.concat(json, '{');
            json = string.concat(json, '"name":"',   POOLS[i].name,          '",');
            json = string.concat(json, '"pool":"',   vm.toString(pools[i]),  '",');
            json = string.concat(json, '"engine":"', vm.toString(engines[i]),'"');
            json = string.concat(json, '}');
            if (i < pools.length - 1) json = string.concat(json, ',');
        }
        json = string.concat(json, ']');
        json = string.concat(json, '}');

        string memory outPath = string.concat(
            "deploy/deployed.",
            vm.toString(block.chainid),
            ".json"
        );
        vm.writeFile(outPath, json);
        console.log("\n[Deploy]    addresses saved to", outPath);

        // 同时打印汇总
        console.log("\n========== Deployment Summary ==========");
        console.log("Chain ID :", block.chainid);
        console.log("USDC     :", usdc);
        console.log("Factory  :", factory);
        console.log("Vault    :", vault);
        console.log("Oracle   :", oracle);
        console.log("NFT      :", nft);
        console.log("Router   :", router);
        for (uint256 i = 0; i < pools.length; i++) {
            console.log("Pool[%s] %s", i, POOLS[i].name);
            console.log("         pool  :", pools[i]);
            console.log("         engine:", engines[i]);
        }
        console.log("=========================================");
    }
}
