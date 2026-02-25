// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Pool} from "../Pool.sol";

library PoolDeployer {

    function deployPool(
        address vault,
        address nft,
        address oracle,
        uint256 pxDecimals,
        uint256 initialPrice,
        string memory itemName
    ) external returns (address) {
        Pool pool = new Pool(vault, nft, oracle, pxDecimals, initialPrice, itemName);
        return address(pool);
    }

}
