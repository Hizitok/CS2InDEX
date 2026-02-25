// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import {LiquidationEngine} from "../Liquidation.sol";

library EngineDeployer {

    function deployEngine(
        address pool,
        address nft,
        address oracle,
        uint256 pxDecimals
    ) external returns (address) {
        LiquidationEngine engine = new LiquidationEngine(pool, nft, oracle, pxDecimals);
        return address(engine);
    }
}
