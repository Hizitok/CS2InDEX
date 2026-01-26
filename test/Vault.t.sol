// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Base.t.sol";

contract VaultTest is BaseTest {

    function test_Deposit() public {
        uint256 depositAmount = 1000e6;

        vm.prank(alice);
        vault.deposit(depositAmount);

        assertEq(vault.balanceOf(alice), depositAmount);
        assertEq(vault.availableBalance(alice), depositAmount);
        assertEq(usdc.balanceOf(alice), INITIAL_BALANCE - depositAmount);
    }

    function test_Deposit_RevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("Zero amount");
        vault.deposit(0);
    }

    function test_Withdraw() public {
        uint256 depositAmount = 1000e6;

        // Deposit first
        vm.prank(alice);
        vault.deposit(depositAmount);

        // Withdraw
        vm.prank(alice);
        vault.withdraw(500e6);

        assertEq(vault.balanceOf(alice), 500e6);
        assertEq(usdc.balanceOf(alice), INITIAL_BALANCE - 500e6);
    }

    function test_Withdraw_RevertInsufficientBalance() public {
        vm.prank(alice);
        vault.deposit(100e6);

        vm.prank(alice);
        vm.expectRevert("Insufficient available balance");
        vault.withdraw(200e6);
    }

    function test_Withdraw_RevertWhenLocked() public {
        // Deploy pool and authorize it
        (address pool, , ) = _deployPool("AK47-Redline", AK47_INITIAL_PRICE);

        // Deposit
        vm.prank(alice);
        vault.deposit(1000e6);

        // Lock balance
        vm.prank(pool);
        vault.lockBalance(alice, 600e6);

        // Try to withdraw more than available
        vm.prank(alice);
        vm.expectRevert("Insufficient available balance");
        vault.withdraw(500e6); // Available is only 400
    }

    function test_LockBalance() public {
        (address pool, , ) = _deployPool("AK47-Redline", AK47_INITIAL_PRICE);

        vm.prank(alice);
        vault.deposit(1000e6);

        vm.prank(pool);
        vault.lockBalance(alice, 600e6);

        assertEq(vault.balanceOf(alice), 1000e6);
        assertEq(vault.availableBalance(alice), 400e6);

        (uint256 total, uint256 locked, uint256 available) = vault.getUserBalanceInfo(alice);
        assertEq(total, 1000e6);
        assertEq(locked, 600e6);
        assertEq(available, 400e6);
    }

    function test_UnlockBalance() public {
        (address pool, , ) = _deployPool("AK47-Redline", AK47_INITIAL_PRICE);

        vm.prank(alice);
        vault.deposit(1000e6);

        vm.prank(pool);
        vault.lockBalance(alice, 600e6);

        vm.prank(pool);
        vault.unlockBalance(alice, 300e6);

        assertEq(vault.availableBalance(alice), 700e6);
    }

    function test_InternalTransfer() public {
        (address pool, , ) = _deployPool("AK47-Redline", AK47_INITIAL_PRICE);

        vm.prank(alice);
        vault.deposit(1000e6);

        vm.prank(bob);
        vault.deposit(500e6);

        // Pool transfers from alice to bob
        vm.prank(pool);
        vault.internalTransfer(alice, bob, 300e6);

        assertEq(vault.balanceOf(alice), 700e6);
        assertEq(vault.balanceOf(bob), 800e6);
    }

    function test_InternalTransfer_RevertUnauthorized() public {
        vm.prank(alice);
        vault.deposit(1000e6);

        // Non-pool tries to transfer
        vm.prank(carol);
        vm.expectRevert("Only authorized pool");
        vault.internalTransfer(alice, bob, 100e6);
    }

    function test_TransferAndLock() public {
        (address pool, , ) = _deployPool("AK47-Redline", AK47_INITIAL_PRICE);

        vm.prank(alice);
        vault.deposit(1000e6);

        vm.prank(pool);
        vault.transferAndLock(alice, pool, 600e6);

        assertEq(vault.balanceOf(alice), 400e6);
        assertEq(vault.balanceOf(pool), 600e6);
        assertEq(vault.availableBalance(alice), 400e6); // All remaining is available
    }

    function test_SetPool_OnlyOwner() public {
        address randomPool = address(0x123);

        // Owner can set
        vault.setPool(randomPool, true);
        assertTrue(vault.isPoolAuthorized(randomPool));

        // Non-owner cannot
        vm.prank(alice);
        vm.expectRevert();
        vault.setPool(randomPool, false);
    }

    function test_EmergencyWithdraw() public {
        // Send random token to vault
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(address(vault), 1000e18);

        // Owner can withdraw
        vault.emergencyWithdraw(address(randomToken), 500e18);

        assertEq(randomToken.balanceOf(owner), 500e18);
    }

    function test_EmergencyWithdraw_RevertSupportedToken() public {
        vm.expectRevert("Cannot withdraw supported token");
        vault.emergencyWithdraw(address(usdc), 100e6);
    }

    function test_GetVaultStats() public {
        vm.prank(alice);
        vault.deposit(1000e6);

        (address token, uint256 total, uint256 actual) = vault.getVaultStats();

        assertEq(token, address(usdc));
        assertEq(total, 1000e6);
        assertEq(actual, 1000e6);
    }
}
