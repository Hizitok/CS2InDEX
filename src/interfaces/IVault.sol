// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVault {

    // ── Emergency Pause ───────────────────────────────────────────────────────

    /** @notice Pause new deposits (owner only) */
    function pause() external;

    /** @notice Resume deposits (owner only) */
    function unpause() external;

    /** @notice Returns true when the vault is paused */
    function paused() external view returns (bool);

    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Transfer tokens internally between accounts
     * @param from Source address
     * @param to Destination address
     * @param amount Amount to transfer
     */
    function internalTransfer(address from, address to, uint256 amount) external;

    /**
     * @notice Deposit tokens into the vault on behalf of a beneficiary
     * @param beneficiary Address to credit
     * @param amount Amount to deposit
     */
    function depositFor(address beneficiary, uint256 amount) external;

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
     * @notice Withdraw on behalf of a user (Router only — caller must be authorized)
     * @param user Account to debit
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function withdrawFor(address user, address to, uint256 amount) external;

    /**
     * @notice Get user's total balance in the vault
     * @param user User address
     * @return User's balance
     */
    function balanceOf(address user) external view returns (uint256);

}
