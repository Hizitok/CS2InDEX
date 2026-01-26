// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Engine
 * @notice Legacy aggregator file - imports all engine contracts
 * @dev For backward compatibility. Import individual contracts directly:
 *      - LiquidationEngine.sol
 *      - ADLEngine.sol
 *      - CS2IndexOracle.sol
 */

// Import individual engine contracts
import {LiquidationEngine} from "./LiquidationEngine.sol";
import {ADLEngine} from "./ADLEngine.sol";
import {CS2IndexOracle} from "./CS2IndexOracle.sol";

// Re-export for backward compatibility
// This allows existing code to continue using:
// import {LiquidationEngine, ADLEngine, CS2IndexOracle} from "./Engine.sol";
