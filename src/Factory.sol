// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "./libraries/Ownable.sol";
import {Vault} from "./Vault.sol";
import {positionNFT} from "./PositionNFT.sol";
import {IndexOracle} from "./IndexOracle.sol";
import {PoolDeployer} from "./libraries/PoolDeployer.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IPool} from "./interfaces/IPool.sol";

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
    error InvalidStatus();

    address public vault;
    address public oracle;
    address public nft;

    // pool address => PoolInfo
    mapping(address => PoolInfo) internal _pools;
    address[] public allPools;

    constructor(address _supportedToken) 
        Ownable(msg.sender) 
    {
        if(_supportedToken == address(0)) revert InvalidStatus();

        // Deploy shared contracts
        vault = address(new Vault(_supportedToken));
        oracle = address(new IndexOracle());
        nft = address(new positionNFT());
    }

    modifier isMyPool(address pool) {
        if(_pools[pool].factory == address(this)) revert NotMyPool();
        _;
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
        if(bytes(itemName).length == 0 || initialPrice == 0) revert InvalidStatus();

        // Deploy Pool via library
        poolAddr = PoolDeployer.deployPool(vault, nft, oracle, pxDecimals, initialPrice, itemName);
        if(_pools[poolAddr].pool != address(0)) revert InvalidStatus();

        // Deploy LiquidationEngine via library
        engineAddr = PoolDeployer.deployEngine(poolAddr, nft, oracle, pxDecimals);

        // Wire permissions
        positionNFT(nft).setPool(poolAddr, true);
        Vault(vault).setPool(poolAddr, true);
        IOracle(oracle).addPool(poolAddr);
        IPool(poolAddr).setEngine(engineAddr);

        // Store pool info
        _pools[poolAddr] = PoolInfo({
            factory: address(this),
            pool: poolAddr,
            engine: engineAddr,
            itemName: itemName,
            deployedAt: block.timestamp
        });

        allPools.push(poolAddr);

        emit PoolCreated(poolAddr, engineAddr, itemName, initialPrice);
    }

    // ======== Admin ======== //

    /**
     * @notice Update oracle price for a pool
     * @dev Factory is oracle owner, so it relays price updates
     */
    function updatePrice(address pool, uint256 newPrice) external onlyOwner isMyPool(pool){
        IOracle(oracle).updateIndexPrice(pool, newPrice);
        emit OraclePriceUpdated(pool, newPrice);
    }

    /**
     * @notice Trigger funding rate settlement for a pool
     */
    function applyFundingRate(address pool) external onlyOwner isMyPool(pool){
        IOracle(oracle).applyFundingRate(pool);
    }

    /**
     * @notice Collect trading fees from a pool
     */
    function collectFees(address pool, address to) external onlyOwner isMyPool(pool){
        IPool(pool).collectFees(to);
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
            PoolInfo memory info,
            uint256 lastPrice,
            uint256 oraclePrice_
        )
    {
        info = _pools[pool];
        if(info.factory == address(this)) revert NotMyPool();

        lastPrice = IPool(info.pool).getLastPrice();
        oraclePrice_ = IOracle(oracle).oraclePrice(info.pool);
    }
}
