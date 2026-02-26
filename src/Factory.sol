// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "./libraries/Ownable.sol";
import {Vault} from "./Vault.sol";
import {positionNFT} from "./PositionNFT.sol";
import {IndexOracle} from "./IndexOracle.sol";
import {PoolDeployer} from "./libraries/PoolDeployer.sol";
import {EngineDeployer} from "./libraries/EngineDeployer.sol";
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
    address public router;

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
        if(_pools[pool].factory != address(this)) revert NotMyPool();
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
        engineAddr = EngineDeployer.deployEngine(poolAddr, nft, oracle, pxDecimals);

        // Wire permissions
        positionNFT(nft).setPool(poolAddr, true);
        Vault(vault).setPool(poolAddr, true);
        IOracle(oracle).addPool(poolAddr);
        IPool(poolAddr).setEngine(engineAddr);
        // Wire router if already registered
        if (router != address(0)) {
            IPool(poolAddr).setRouter(router);
        }

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
     * @notice Register the Router and authorize it in Vault + all existing pools.
     * @dev Call this once after deploying the Router. New pools created afterward
     *      are wired automatically inside createPool().
     * @param _router Deployed Router address
     */
    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "Factory: zero router");

        // Deauthorize old router if one was set
        if (router != address(0)) {
            Vault(vault).setPool(router, false);
        }

        router = _router;

        // Authorize in Vault (needed for withdrawFor)
        Vault(vault).setPool(_router, true);

        // Wire to all existing pools
        for (uint256 i = 0; i < allPools.length; i++) {
            IPool(allPools[i]).setRouter(_router);
        }
    }

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
        isMyPool(pool)
        returns (
            PoolInfo memory info,
            uint256 lastPrice,
            uint256 oraclePrice
        )
    {
        info = _pools[pool];
        lastPrice = IPool(info.pool).getLastPrice();
        oraclePrice = IOracle(oracle).oraclePrice(info.pool);
    }
}
