// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Ownable.sol";
import "../interfaces/IERC165.sol";
import "../interfaces/ERC721/IERC721.sol";
import "../interfaces/ERC721/ERC721Utils.sol";

contract PosERC721 is Ownable, IERC721 {

    error InvalidReceiver(address receiver);
    error InvalidSender(address sender);
    error NonexistentToken(uint256 tokenId);

    mapping(uint256 tokenId => address) private _owners;

    mapping(address owner => uint256) private _balances;

    mapping(uint256 tokenId => address) private _tokenApprovals;

    mapping(address owner => mapping(address operator => bool)) private _operatorApprovals;

    constructor() Ownable(msg.sender) {}

    //-------------ERC 165 Part ---------------

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        returns (bool)
    {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    //-------------ERC 721 Part ---------------

    function balanceOf(address owner)
        external
        view
        override
    returns (uint256 balance) {
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId)
        external
        view
        override
    returns (address owner) {
        owner = _owners[tokenId];
        if (owner == address(0)) {
            revert NonexistentToken(tokenId);
        }
        return owner;
    }
    
    function getApproved(uint256 tokenId)
        public
        view
        override
        returns (address operator)
    {
        if (_owners[tokenId] == address(0)) {
            revert NonexistentToken(tokenId);
        }
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address owner, address operator)
        public
        view
        override
        returns (bool)
    {
        return _operatorApprovals[owner][operator];
    }

    function approve(address to, uint256 tokenId) public override {
        address owner = _owners[tokenId];
        if (owner == address(0)) {
            revert NonexistentToken(tokenId);
        }
        require(to != owner, "PositionNFT: approve to current owner");

        address sender = msg.sender;
        // Only approved by owner or operator 
        require(
            sender == owner || _operatorApprovals[owner][sender],
            "PositionNFT: not owner nor approved for all"
        );

        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public override {
        address owner = msg.sender;
        require(operator != owner, "No Approve to caller");

        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    function _transfer(address from, address to, uint256 tokenId) private {
        address owner = _owners[tokenId];

        if (owner == address(0)) {
            revert NonexistentToken(tokenId);
        }

        require(owner == from, "Not Owner");

        delete _tokenApprovals[tokenId];

        _owners[tokenId] = to;

        _balances[from] -= 1;
        _balances[to] += 1;

        emit Transfer(from, to, tokenId);
    }

    /// @inheritdoc IERC721
    function transferFrom(address from, address to, uint256 tokenId)
        public
        virtual
        override
    {
        if (to == address(0)) {
            revert InvalidReceiver(address(0));
        }

        address owner = _owners[tokenId];

        if (owner == address(0)) {
            revert NonexistentToken(tokenId);
        }

        if (owner != from) {
            revert InvalidSender(from);
        }

        require(_authorized(tokenId, msg.sender), "Not authorized");

        _transfer(from, to, tokenId);
    }

    function _authorized(uint256 tokenId, address user)
        public 
        view
        returns (bool authorized)
    {
        authorized = (
            user == _owners[tokenId] ||
            user == _tokenApprovals[tokenId] ||
            _operatorApprovals[_owners[tokenId]][user]
        );
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId)
        public
        override
    {
        safeTransferFrom(from, to, tokenId, "");
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        virtual
        override
    {
        transferFrom(from, to, tokenId);
        ERC721Utils.checkOnERC721Received(msg.sender, from, to, tokenId, data);
    }

    // ---- ERC 721 Part Ends ---- //

}
