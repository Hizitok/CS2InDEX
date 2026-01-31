// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICS2InDEX
 * @notice Master interface file that imports all CS2InDEX interfaces
 * @dev Import this file to get access to all protocol interfaces
 */

// Core Interfaces
import "./IPool.sol";
import "./IVault.sol";
import "./IPosition.sol";
import "./IFactory.sol";
import "./IRouter.sol";

// Engine Interfaces
import "./ILiquidationEngine.sol";
import "./IADLEngine.sol";
import "./IOracle.sol";

// Token Interfaces
import "./IERC20.sol";
import "./IERC165.sol";
import "./ERC721/IERC721.sol";
import "./ERC721/IERC721Receiver.sol";

// Types
import "./OrderTypes.sol";

/**
 * @dev This file serves as a central import point for all CS2InDEX interfaces
 *
 * Usage:
 * import "src/interfaces/ICS2InDEX.sol";
 *
 * This gives you access to:
 * - IPool: Trading pool interface
 * - IVault: Collateral vault interface
 * - IPosition: Position NFT interface
 * - IFactory: Pool factory interface
 * - IRouter: Router for batch operations
 * - ILiquidationEngine: Liquidation engine interface
 * - IADLEngine: Auto-deleveraging engine interface
 * - IOracle: Price oracle interface
 * - OrderTypes: Common types and structs
 * - ERC20, ERC721, ERC165: Standard token interfaces
 */
