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

    function withdrawTo(address to, uint256 amount) external;

    /**
     * @notice Get user's total balance in the vault
     * @param user User address
     * @return User's balance
     */
    function balanceOf(address user) external view returns (uint256);

}
