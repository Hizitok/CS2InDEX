// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVault {

    /**
     * @notice Transfer tokens internally between accounts
     * @param from Source address
     * @param to Destination address
     * @param amount Amount to transfer
     */
    function internalTransfer(address from, address to, uint256 amount) external;

    /**
     * @notice Deposit tokens into the vault
     * @param amount Amount to deposit
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Withdraw tokens from the vault
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Get user's total balance in the vault
     * @param user User address
     * @return User's balance
     */
    function balanceOf(address user) external view returns (uint256);

    /**
     * @notice Get user's available balance (not locked)
     * @param user User address
     * @return Available balance
     */
    function availableBalance(address user) external view returns (uint256);

    /**
     * @notice Lock user balance for position margin
     * @param user User address
     * @param amount Amount to lock
     */
    function lockBalance(address user, uint256 amount) external;

    /**
     * @notice Unlock user balance after position closed
     * @param user User address
     * @param amount Amount to unlock
     */
    function unlockBalance(address user, uint256 amount) external;

    /**
     * @notice Transfer and lock in one operation
     * @param from User address
     * @param to Pool address
     * @param amount Amount to transfer and lock
     */
    function transferAndLock(address from, address to, uint256 amount) external;

    /**
     * @notice Get comprehensive user balance info
     * @param user User address
     * @return total Total balance
     * @return locked Locked balance
     * @return available Available for withdrawal
     */
    function getUserBalanceInfo(address user)
        external
        view
        returns (uint256 total, uint256 locked, uint256 available);
}
