// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/libraries/IzitOrderStatisticsTree.sol";

contract OrderStatisticsTreeTest is Test {
    using IzitOrderStatisticsTree for IzitOrderStatisticsTree.Tree;

    IzitOrderStatisticsTree.Tree internal tree;

    function setUp() public {
        // Tree is initialized empty
    }

    function testInsertAndContains() public {
        assertFalse(tree.contains(100));

        tree.insert(100, 1001);
        assertTrue(tree.contains(100));
        assertEq(tree.getValue(100), 1001);
    }

    function testInsertMultiple() public {
        tree.insert(50, 1);
        tree.insert(30, 2);
        tree.insert(70, 3);
        tree.insert(20, 4);
        tree.insert(40, 5);

        assertEq(tree.size(), 5);
        assertTrue(tree.contains(50));
        assertTrue(tree.contains(30));
        assertTrue(tree.contains(70));
        assertTrue(tree.contains(20));
        assertTrue(tree.contains(40));
    }

    function testGetMinMax() public {
        tree.insert(50, 1);
        tree.insert(30, 2);
        tree.insert(70, 3);
        tree.insert(20, 4);
        tree.insert(90, 5);

        (uint256 minKey, uint256 minVal) = tree.getMin();
        assertEq(minKey, 20);
        assertEq(minVal, 4);

        (uint256 maxKey, uint256 maxVal) = tree.getMax();
        assertEq(maxKey, 90);
        assertEq(maxVal, 5);
    }

    function testGetRank() public {
        // Insert keys: 20, 30, 40, 50, 70
        tree.insert(50, 1);
        tree.insert(30, 2);
        tree.insert(70, 3);
        tree.insert(20, 4);
        tree.insert(40, 5);

        assertEq(tree.getRank(20), 1); // smallest
        assertEq(tree.getRank(30), 2);
        assertEq(tree.getRank(40), 3);
        assertEq(tree.getRank(50), 4);
        assertEq(tree.getRank(70), 5); // largest
    }

    function testGetKthSmallest() public {
        // Insert keys: 20, 30, 40, 50, 70
        tree.insert(50, 1);
        tree.insert(30, 2);
        tree.insert(70, 3);
        tree.insert(20, 4);
        tree.insert(40, 5);

        (uint256 key1, uint256 val1) = tree.getKthSmallest(1);
        assertEq(key1, 20);
        assertEq(val1, 4);

        (uint256 key2, uint256 val2) = tree.getKthSmallest(2);
        assertEq(key2, 30);
        assertEq(val2, 2);

        (uint256 key3, uint256 val3) = tree.getKthSmallest(3);
        assertEq(key3, 40);
        assertEq(val3, 5);

        (uint256 key5, uint256 val5) = tree.getKthSmallest(5);
        assertEq(key5, 70);
        assertEq(val5, 3);
    }

    function testCountLessThan() public {
        // Insert keys: 20, 30, 40, 50, 70
        tree.insert(50, 1);
        tree.insert(30, 2);
        tree.insert(70, 3);
        tree.insert(20, 4);
        tree.insert(40, 5);

        assertEq(tree.countLessThan(25), 1);  // Only 20
        assertEq(tree.countLessThan(35), 2);  // 20, 30
        assertEq(tree.countLessThan(45), 3);  // 20, 30, 40
        assertEq(tree.countLessThan(60), 4);  // 20, 30, 40, 50
        assertEq(tree.countLessThan(100), 5); // All
        assertEq(tree.countLessThan(20), 0);  // None
    }

    function testGetKeysLessThan() public {
        // Insert keys: 20, 30, 40, 50, 70
        tree.insert(50, 1);
        tree.insert(30, 2);
        tree.insert(70, 3);
        tree.insert(20, 4);
        tree.insert(40, 5);

        (uint256[] memory keys, uint256[] memory values) = tree.getKeysLessThan(45, 10);

        assertEq(keys.length, 3);
        assertEq(keys[0], 20);
        assertEq(keys[1], 30);
        assertEq(keys[2], 40);

        assertEq(values[0], 4);
        assertEq(values[1], 2);
        assertEq(values[2], 5);
    }

    function testGetKeysLessThanWithLimit() public {
        tree.insert(10, 1);
        tree.insert(20, 2);
        tree.insert(30, 3);
        tree.insert(40, 4);
        tree.insert(50, 5);

        // Request only first 2 results
        (uint256[] memory keys, uint256[] memory values) = tree.getKeysLessThan(100, 2);

        assertEq(keys.length, 2);
        assertEq(keys[0], 10);
        assertEq(keys[1], 20);
    }

    function testRemove() public {
        tree.insert(50, 1);
        tree.insert(30, 2);
        tree.insert(70, 3);
        tree.insert(20, 4);
        tree.insert(40, 5);

        assertEq(tree.size(), 5);
        assertTrue(tree.contains(30));

        tree.remove(30);

        assertEq(tree.size(), 4);
        assertFalse(tree.contains(30));
        assertTrue(tree.contains(50));
        assertTrue(tree.contains(70));
        assertTrue(tree.contains(20));
        assertTrue(tree.contains(40));
    }

    function testRemoveAndReinsert() public {
        tree.insert(50, 1);
        tree.insert(30, 2);

        tree.remove(30);
        assertFalse(tree.contains(30));

        tree.insert(30, 999);
        assertTrue(tree.contains(30));
        assertEq(tree.getValue(30), 999);
    }

    function testRankAfterRemoval() public {
        // Insert keys: 20, 30, 40, 50, 70
        tree.insert(50, 1);
        tree.insert(30, 2);
        tree.insert(70, 3);
        tree.insert(20, 4);
        tree.insert(40, 5);

        // Remove 30
        tree.remove(30);

        // New order: 20, 40, 50, 70
        assertEq(tree.getRank(20), 1);
        assertEq(tree.getRank(40), 2);
        assertEq(tree.getRank(50), 3);
        assertEq(tree.getRank(70), 4);
    }

    function testLiquidationScenario() public {
        // Simulate liquidation prices for positions
        // Lower price = closer to liquidation = higher priority
        tree.insert(45000e6, 1001); // Position 1001 liquidates at $45k
        tree.insert(47000e6, 1002); // Position 1002 liquidates at $47k
        tree.insert(43000e6, 1003); // Position 1003 liquidates at $43k (most at risk)
        tree.insert(50000e6, 1004); // Position 1004 liquidates at $50k
        tree.insert(44000e6, 1005); // Position 1005 liquidates at $44k

        // Find most at-risk position
        (uint256 minPrice, uint256 posId) = tree.getMin();
        assertEq(minPrice, 43000e6);
        assertEq(posId, 1003);

        // Get rank of position 1005
        uint256 rank = tree.getRank(44000e6);
        assertEq(rank, 2); // Second most at-risk

        // Count positions liquidatable if price drops to $46k
        uint256 atRiskCount = tree.countLessThan(46000e6);
        assertEq(atRiskCount, 3); // Positions at 43k, 44k, 45k

        // Get first 2 positions to liquidate
        (uint256[] memory prices, uint256[] memory positions) = tree.getKeysLessThan(100000e6, 2);
        assertEq(positions[0], 1003); // Most at risk
        assertEq(positions[1], 1005); // Second most at risk
    }

    function testEmptyTree() public {
        assertTrue(tree.isEmpty());
        assertEq(tree.size(), 0);
    }

    function testSingleElement() public {
        tree.insert(100, 999);

        assertFalse(tree.isEmpty());
        assertEq(tree.size(), 1);
        assertEq(tree.getRank(100), 1);

        (uint256 key, uint256 val) = tree.getKthSmallest(1);
        assertEq(key, 100);
        assertEq(val, 999);
    }

    function testStressInsert() public {
        // Insert 100 elements
        for (uint256 i = 1; i <= 100; i++) {
            tree.insert(i * 1000, i);
        }

        assertEq(tree.size(), 100);

        // Verify first and last
        (uint256 minKey, uint256 minVal) = tree.getMin();
        assertEq(minKey, 1000);
        assertEq(minVal, 1);

        (uint256 maxKey, uint256 maxVal) = tree.getMax();
        assertEq(maxKey, 100000);
        assertEq(maxVal, 100);

        // Verify middle element
        assertEq(tree.getRank(50000), 50);
    }

    function testRevertOnDuplicateKey() public {
        tree.insert(100, 1);

        vm.expectRevert("Key already exists");
        tree.insert(100, 2);
    }

    function testRevertOnRemoveNonExistent() public {
        vm.expectRevert("Key not found");
        tree.remove(999);
    }

    function testRevertOnGetValueNonExistent() public {
        vm.expectRevert("Key not found");
        tree.getValue(999);
    }

    function testRevertOnGetRankNonExistent() public {
        tree.insert(100, 1);

        vm.expectRevert("Key not found");
        tree.getRank(999);
    }

    function testRevertOnGetKthSmallestOutOfRange() public {
        tree.insert(100, 1);
        tree.insert(200, 2);

        vm.expectRevert("k out of range");
        tree.getKthSmallest(3); // Only 2 elements

        vm.expectRevert("k out of range");
        tree.getKthSmallest(0); // k must be >= 1
    }
}
