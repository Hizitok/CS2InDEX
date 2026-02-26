// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Pausable
 * @notice Emergency pause mechanism for critical contract functions
 * @dev Inherit this contract and apply `whenNotPaused` to state-changing functions
 *      that should halt during an incident. Withdrawal/exit functions should NOT
 *      use `whenNotPaused` so users can always recover their funds.
 */
abstract contract Pausable {

    bool private _paused;

    event Paused(address indexed account);
    event Unpaused(address indexed account);

    error EnforcedPause();

    /**
     * @notice Reverts if the contract is paused
     */
    modifier whenNotPaused() {
        if (_paused) revert EnforcedPause();
        _;
    }

    /**
     * @notice Returns true if the contract is currently paused
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Internal pause — call from an onlyOwner external wrapper
     */
    function _pause() internal {
        _paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @dev Internal unpause — call from an onlyOwner external wrapper
     */
    function _unpause() internal {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}
