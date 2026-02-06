// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "./libraries/Ownable.sol";
import {Pool} from "./Pool.sol";
import {Vault} from "./Vault.sol";
import {positionNFT} from "./PositionNFT.sol";
import {IndexOracle} from "./IndexOracle.sol";
import {LiquidationEngine} from "./Liquidation.sol";
import {IFactory} from "./interfaces/IFactory.sol";

/**
 * @title CS2InDEX Factory
 * @notice Deploys and wires up all contracts for each trading pool:
 *
 *   Shared (one instance, deployed by constructor):
 *     [Vault]        — central collateral vault
 *     [IndexOracle]  — price oracle
 *     [positionNFT]  — position NFTs
 *
 *   Per pool:
 *     [Pool]              — orderbook + matching engine
 *     [LiquidationEngine] — monitors margin, force-liquidates via Pool
 *
 *   Permission wiring on createPool:
 *     Vault.setPool(pool)              → Pool can internalTransfer
 *     positionNFT.setPool(pool)        → Pool can mint/update positions
 *     IndexOracle.addPool(pool)        → Pool can submit VTWAP samples
 *     Pool.setEngine(engine)           → Engine can forceLiquidate
 */
contract CS2InDEXFactory is Ownable, IFactory {

    error NotMyPool();

    address public vault;
    address public oracle;
    address public nft;

    // pool address => PoolInfo
    mapping(address => PoolInfo) internal _pools;
    address[] public allPools;

    constructor(address _supportedToken) Ownable(msg.sender) {
        require(_supportedToken != address(0), "Invalid token");

        // Deploy shared contracts
        vault = address(new Vault(_supportedToken));
        oracle = address(new IndexOracle());
        nft = address(new positionNFT());
    }

    // ======== Pool Deployment ======== //

    /**
     * @notice Deploy a full trading pool for a CS2 item
     * @param itemName  e.g. "AK47-Redline"
     * @param initialPrice  Initial price (scaled by pxDecimals)
     * @param pxDecimals  Price decimal places (e.g. 2 means prices are x100)
     */
    function createPool(
        string memory itemName,
        uint256 initialPrice,
        uint256 pxDecimals
    )
        external
        onlyOwner
        returns (address poolAddr, address engineAddr)
    {
        require(initialPrice > 0, "Invalid price");
        require(bytes(itemName).length > 0, "Empty name");

        // 1. Deploy Pool
        Pool pool = new Pool(
            vault,
            nft,
            oracle,
            pxDecimals,
            initialPrice,
            itemName
        );
        poolAddr = address(pool);
        require(_pools[poolAddr].pool == address(0), "Pool exists");

        // 2. Deploy LiquidationEngine (one per pool)
        LiquidationEngine engine = new LiquidationEngine(
            poolAddr,
            nft,
            oracle,
            pxDecimals
        );
        engineAddr = address(engine);

        // 3. Wire permissions
        positionNFT(nft).setPool(poolAddr, true);
        Vault(vault).setPool(poolAddr, true);
        IndexOracle(oracle).addPool(poolAddr);
        pool.setEngine(engineAddr);

        // 4. Store
        _pools[poolAddr] = PoolInfo({
            pool: poolAddr,
            engine: engineAddr,
            itemName: itemName,
            deployedAt: block.timestamp,
            active: true
        });

        allPools.push(poolAddr);

        emit PoolCreated(poolAddr, engineAddr, itemName, initialPrice);
    }

    // ======== Admin ======== //

    /**
     * @notice Activate / deactivate a pool
     */
    function setPoolStatus(address pool, bool active) external onlyOwner {
        if(_pools[pool].factory == address(this)) revert NotMyPool();
        _pools[pool].active = active;
        emit PoolStatusChanged(pool, active);
    }

    /**
     * @notice Update oracle price for a pool
     * @dev Factory is oracle owner, so it relays price updates
     */
    function updatePrice(address pool, uint256 newPrice) external onlyOwner {
        if(_pools[pool].factory == address(this)) revert NotMyPool();
        IndexOracle(oracle).updateIndexPrice(pool, newPrice);
        emit OraclePriceUpdated(pool, newPrice);
    }

    /**
     * @notice Trigger funding rate settlement for a pool
     */
    function applyFundingRate(address pool) external onlyOwner {
        if(_pools[pool].factory == address(this)) revert NotMyPool();
        IndexOracle(oracle).applyFundingRate(pool);
    }

    /**
     * @notice Collect trading fees from a pool
     */
    function collectFees(address pool, address to) external onlyOwner {
        if(_pools[pool].factory == address(this)) revert NotMyPool();
        Pool(pool).collectFees(to);
    }

    // ======== View ======== //

    function getPoolInfo(address pool) external view returns (PoolInfo memory) {
        return _pools[pool];
    }

    function poolCount() external view returns (uint256) {
        return allPools.length;
    }

    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }

    function isValidPool(address pool) external view returns (bool) {
        return _pools[pool].pool != address(0);
    }

    /**
     * @notice Get pool stats for frontend display
     */
    function getPoolStats(address pool)
        external
        view
        returns (
            address engineAddr,
            string memory itemName,
            bool active,
            uint256 lastPrice,
            uint256 oraclePrice_
        )
    {
        PoolInfo memory info = _pools[pool];
        if(info == address(this)) revert NotMyPool();

        engineAddr = info.engine;
        itemName = info.itemName;
        active = info.active;
        lastPrice = Pool(info.pool).getLastPrice();
        oraclePrice_ = IndexOracle(oracle).oraclePrice(info.pool);
    }
}
