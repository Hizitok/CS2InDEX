// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OrderTypes} from "./OrderTypes.sol";

interface IPosition is OrderTypes {

    /**
     * @notice Create a new position NFT
     * @param pOrder The order details
     * @param owner The owner of the position
     * @return posId The new position ID
     */
    function newNFT(PoolOrder calldata pOrder, address owner, uint256 margin) external returns (OrderId posId);

    /**
     * @notice Get position details
     * @param posId Position ID
     * @return Position data
     */
    function getPosition(OrderId posId) external view returns (Position memory);

    /**
     * @notice Update position data
     * @param posId Position ID
     * @param pos Updated position data
     * @return success if Update is success
     */
    function updatePosition(OrderId posId, Position memory pos) external returns (bool);

    /**
     * @notice Get the opening tick/price of a position
     * @param posId Position ID
     * @return Opening price x 100
     */
    function getOpenTick(OrderId posId) external view returns (uint256);

    /**
     * @notice Get the owner of a position NFT
     * @param tokenId Token ID
     * @return Owner address
     */
    function ownerOf(uint256 tokenId) external view returns (address);

    /**
     * @notice Settle position PnL and return margin
     * @param posId Position ID
     */
    function settlePosition(OrderId posId) external;

    /**
     * @notice Get all positions owned by an address
     * @param owner Owner address
     * @return Array of position IDs
     */
    function getPositionsByOwner(address owner) external view returns (uint256[] memory);

    /**
     * @notice Set pool authorization
     * @param pool Pool address
     * @param authorized Authorization status
     */
    function setPool(address pool, bool authorized) external;

    /**
     * @notice Get total supply of position NFTs
     * @return Total supply
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Get token URI for a position NFT
     * @param tokenId Token ID
     * @return Token URI
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);

    /**
     * @notice Check if a user is authorized
     * @param oID Position ID
     * @param user User address
     * @return True if authorized
     */
    function isAuthorized(OrderId oID, address user) external view returns (bool);


    /**
     * @notice Check if pool is authorized
     * @param pool Pool address
     * @return True if authorized
     */
    function isAuthorizedPool(address pool) external view returns (bool);

    // Events
    event PositionCreated(uint256 indexed tokenId, address indexed owner, bool isShort);
    event PositionUpdated(uint256 indexed tokenId, posStatus status, uint256 openSize, uint256 closeSize);
    event PositionSettled(uint256 indexed tokenId, int256 pnl);
}
