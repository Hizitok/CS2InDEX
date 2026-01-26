// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "./interfaces/IERC20.sol";
import {Ownable} from "./libraries/Ownable.sol";
import {ReentrancyGuard} from "./libraries/ReentrancyGuard.sol";

/**
 * @title Vault
 * @notice Central vault for managing user collateral and internal transfers
 * @dev Supports single token (USDC/USDT/etc.) for simplified margin management
 */
contract Vault is Ownable, ReentrancyGuard {

    // Immutable supported token
    address public immutable supportedToken;

    // Total deposited amount
    uint256 public totalAmount;

    // User balances: user => balance
    // Locked balances is Stored in pool account
    mapping(address => uint256) public balances;

    // Available pools (authorized to call internalTransfer)
    mapping(address => bool) public availablePools;

    // Events
    event PoolUpdated(address indexed pool, bool allowed);

    event Deposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    event Withdrawn(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    event InternalTransfer(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 amount
    );

    // Modifiers
    modifier onlyPool() {
        require(availablePools[msg.sender], "Only authorized pool");
        _;
    }

    constructor(address _supportedToken) Ownable(msg.sender) {
        require(_supportedToken != address(0), "Invalid token address");
        supportedToken = _supportedToken;
    }

    // ======== Admin functions ========

    /**
     * @notice Add or remove authorized pool
     * @param pool Pool address
     * @param allowed Whether pool is authorized
     */
    function setPool(address pool, bool allowed) external onlyOwner {
        require(pool != address(0), "Invalid pool address");
        availablePools[pool] = allowed;
        emit PoolUpdated(pool, allowed);
    }

    // ======== User-facing functions ========

    /**
     * @notice Query user's total balance
     * @param user User address
     * @return Total balance
     */
    function balanceOf(address user) external view returns (uint256) {
        return balances[user];
    }

    /**
     * @notice Query total token held by this contract
     * @return Total token balance
     */
    function totalTokenHeld() external view returns (uint256) {
        return IERC20(supportedToken).balanceOf(address(this));
    }

    /**
     * @notice User deposits collateral
     * @dev Requires prior approval of this contract
     * @param amount Amount to deposit
     */
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");

        // Transfer tokens from user
        bool success = IERC20(supportedToken).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success, "Transfer from failed");

        // Update balances
        totalAmount += amount;
        balances[msg.sender] += amount;

        emit Deposited(msg.sender, supportedToken, amount);
    }

    /**
     * @notice User withdraws collateral
     * @dev Can only withdraw unlocked balance
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");

        uint256 userBalance = balances[msg.sender];

        require(userBalance >= amount, "Insufficient available balance");

        // Update balances
        totalAmount -= amount;
        balances[msg.sender] = userBalance - amount;

        // Transfer tokens to user
        bool success = IERC20(supportedToken).transfer(msg.sender, amount);
        require(success, "Transfer failed");

        emit Withdrawn(msg.sender, supportedToken, amount);
    }

    /**
     * @notice Emergency withdrawal of unsupported tokens (owner only)
     * @dev For recovering accidentally sent tokens
     * @param token Token address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount)
        external
        onlyOwner
    {
        require(token != supportedToken, "Cannot withdraw supported token");
        require(amount > 0, "Zero amount");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance >= amount, "Insufficient balance");

        bool success = IERC20(token).transfer(msg.sender, amount);
        require(success, "Transfer failed");

        emit Withdrawn(msg.sender, token, amount);
    }

    // ======== Pool functions (authorized operators only) ========

    /**
     * @notice Internal transfer between accounts
     * @dev Used by pools for margin transfers, PnL settlement, fees, etc.
     * @param from Source address
     * @param to Destination address
     * @param amount Amount to transfer
     */
    function internalTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyPool nonReentrant {
        require(amount > 0, "Zero amount");
        require(from != address(0) && to != address(0), "Invalid address");

        uint256 fromBalance = balances[from];
        require(fromBalance >= amount, "Insufficient balance");

        // Update balances
        balances[from] = fromBalance - amount;
        balances[to] += amount;

        emit InternalTransfer(msg.sender, from, to, amount);
    }

    // ======== View helpers ========

    /**
     * @notice Check if pool is authorized
     * @param pool Pool address
     * @return Whether pool is authorized
     */
    function isPoolAuthorized(address pool) external view returns (bool) {
        return availablePools[pool];
    }

    /**
     * @notice Get vault statistics
     * @return _supportedToken Supported token address
     * @return _totalAmount Total deposited amount
     * @return _actualBalance Actual token balance in contract
     */
    function getVaultStats()
        external
        view
        returns (
            address _supportedToken,
            uint256 _totalAmount,
            uint256 _actualBalance
        )
    {
        _supportedToken = supportedToken;
        _totalAmount = totalAmount;
        _actualBalance = IERC20(supportedToken).balanceOf(address(this));
    }
}
