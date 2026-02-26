// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Prevents reentrant calls to guarded functions.
 *
 * Apply `nonReentrant` to external functions that must not be re-entered.
 * `nonReentrantView` can be used on view functions to prevent reads during
 * mid-execution state.
 */
abstract contract ReentrancyGuard {

    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    // Initialised to NOT_ENTERED so the first call pays a warm SSTORE
    // (cheaper than a cold one) and each subsequent call gets the EIP-2200
    // gas refund when resetting back to NOT_ENTERED.
    uint256 private _status = NOT_ENTERED;

    error ReentrancyGuardReentrantCall();

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    modifier nonReentrantView() {
        if (_reentrancyGuardEntered()) revert ReentrancyGuardReentrantCall();
        _;
    }

    function _nonReentrantBefore() private {
        if (_reentrancyGuardEntered()) revert ReentrancyGuardReentrantCall();
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        _status = NOT_ENTERED;
    }

    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}
