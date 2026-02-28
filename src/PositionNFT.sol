// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "./libraries/Ownable.sol";
import {PosERC721} from "./libraries/PosERC721.sol";
import {OrderTypes} from "./interfaces/OrderTypes.sol";

/**
 * @title positionNFT
 * @notice ERC721 NFT representing perpetual trading positions
 * @dev Each position is minted as an NFT that can be transferred
 */
contract positionNFT is OrderTypes, PosERC721 {

    uint256 private tokenCount;

    // Token ID => Position data
    mapping(uint256 => Position) private _positions;

    // Token ID => Pool address
    mapping(uint256 => address) private _pools;

    // Authorized pools (can mint and update positions)
    mapping(address => bool) private _authorizedPools;

    // Events
    event PositionCreated(
        uint256 indexed tokenId,
        address indexed owner,
        Position pos
    );

    event PositionUpdated(
        uint256 indexed tokenId,
        Position pos
    );

    event PositionSettled(
        uint256 indexed tokenId,
        address indexed owner
    );

    // Errors
    error PosNotExist();
    error InvalidAddress();
    error InvalidOwner();
    error NotAuthorized();

    modifier onlyPool() {
        require(_authorizedPools[msg.sender], "Only authorized pool");
        _;
    }

    constructor() {}

    // ======== Admin Functions ========

    /**
     * @notice Add or remove authorized pool
     * @param pool Pool address
     * @param allowed Whether pool is authorized
     */
    function setPool(address pool, bool allowed) external onlyOwner {
        if(pool == address(0)) revert InvalidAddress();
        _authorizedPools[pool] = allowed;
    }

    // ======== Position NFT Functions ========

    /**
     * @notice Create a new position NFT
     * @param pOrder Order details
     * @param owner NFT owner
     * @return oID New position ID
     */
    function newNFT(PoolOrder calldata pOrder, address owner, uint256 margin)
        external
        onlyPool
        returns (OrderId oID)
    {
        if(owner == address(0)) revert InvalidOwner();

        tokenCount += 1;
        oID = OrderId.wrap(tokenCount);

        Position memory newPos = Position({
            isShort: pOrder.isSell,
            status: posStatus.pendingOpen,
            openMargin: margin,
            pendingSize: pOrder.size,
            openSize: 0,
            closeSize: 0,
            openAmount: 0,
            closeAmount: 0,
            openFundingIdx: 0,
            closeFundingIdx: 0
        });

        _positions[tokenCount] = newPos;
        _pools[tokenCount] = msg.sender;
        _owners[tokenCount] = owner;
        _balances[owner] += 1;

        emit Transfer(address(0), owner, tokenCount);
        emit PositionCreated(tokenCount, owner, newPos);
    }

    /**
     * @notice Get position data
     * @param oID Position ID
     * @return Position data
     */
    function getPosition(OrderId oID)
        external
        view
        returns (Position memory)
    {
        uint256 id = OrderId.unwrap(oID);
        if( _pools[id]==address(0) ) revert PosNotExist();
        return _positions[id];
    }

    /**
     * @notice Update position data
     * @param oID Position ID
     * @param pos Updated position data
     */
    function updatePosition(OrderId oID, Position memory pos)
        external
        onlyPool
        returns (bool)
    {
        uint256 id = OrderId.unwrap(oID);
        if( _pools[id] == address(0) ) revert PosNotExist();
        if( _pools[id] != msg.sender ) revert NotAuthorized();

        _positions[id] = pos;

        emit PositionUpdated(id, pos);
        return true;
    }

    /**
     * @notice Mark position as settled
     * @param oID Position ID
     */
    function settlePosition(OrderId oID) external onlyPool {
        uint256 id = OrderId.unwrap(oID);
        if( _pools[id] == address(0) ) revert PosNotExist();
        if( _pools[id] != msg.sender ) revert NotAuthorized();
        require(_positions[id].status != posStatus.settled, "Already settled");

        _positions[id].status = posStatus.settled;

        emit PositionSettled(id, _owners[id]);
    }

    /**
     * @notice Get Pool of a position
     * @param orderId Position ID
     * @return Pool pool address
     */  
    function getPool(OrderId orderId)
        external
        view
        returns (address)
    {
        return _pools[OrderId.unwrap(orderId)];
    }
    

    /**
     * @notice Get opening price of a position
     * @param orderId Position ID
     * @return Opening price x 100
     */
    function getOpenTick(OrderId orderId)
        external
        view
        returns (uint256)
    {
        uint256 id = OrderId.unwrap(orderId);
        if( _pools[id] == address(0) ) revert PosNotExist();
        // Calculate average opening price
        if(_positions[id].openSize == 0) {
            return 0;
        }

        return _positions[id].openAmount / _positions[id].openSize;
    }

    /**
     * @notice Check if position is authorized
     * @param oID Position ID
     * @param user User Address
     * @return Whether user is authorized
     */
    function isAuthorized(OrderId oID, address user) external view returns (bool) {
        uint256 id = OrderId.unwrap(oID);
        return (_pools[id] == user) || _authorized(id, user);
    }

    /**
     * @notice Check if position is settled
     * @param oID Position ID
     * @return Whether position is settled
     */
    function isSettled(OrderId oID) external view returns (bool) {
        uint256 id = OrderId.unwrap(oID);
        return _positions[id].status == posStatus.settled;
    }

    /**
     * @notice Check if pool is authorized
     * @param pool Pool address
     * @return Whether pool is authorized
     */
    function isPoolAuthorized(address pool) external view returns (bool) {
        return _authorizedPools[pool];
    }


    /**
     * @notice Get total number of positions
     * @return Total token count
     */
    function totalSupply() external view returns (uint256) {
        return tokenCount;
    }

    /**
     * @notice Get all positions owned by an address
     * @param owner Address to query
     * @return tokenIds Array of token IDs
     * @return positions Array of position data
     */
    function getPositionsByOwner(address owner)
        external
        view
        returns (uint256[] memory tokenIds, Position[] memory positions)
    {
        uint256 balance = _balances[owner];
        tokenIds = new uint256[](balance);
        positions = new Position[](balance);

        uint256 index = 0;
        for (uint256 i = 1; i <= tokenCount && index < balance; i++) {
            if(_owners[i] == owner) {
                tokenIds[index] = i;
                positions[index] = _positions[i];
                index++;
            }
        }
    }
}
