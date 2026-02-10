// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/libraries/IzitOSTreeMinimum.sol";

/**
 * @title OrderStatisticsTreeTest
 * @notice Tests for IzitOSTreeMinimum - minimal red-black tree implementation
 * @dev Tests core functionality: insert, remove, getRank, getMin, getMax, contains, isEmpty
 */
contract OrderStatisticsTreeTest is Test, IzitOSTreeMinimum {

    IzitOSTreeMinimum.Tree internal tree;

    // Implement the abstract _less function for testing
    // Compares keys directly (smaller key = higher priority)
    function _less(uint256 a, uint256 b) internal pure override returns (bool) {
        return a < b;
    }

    function setUp() public {
        // Tree is initialized empty
    }

    /*//////////////////////////////////////////////////////////////
                        INSERT AND CONTAINS TESTS
    //////////////////////////////////////////////////////////////*/

    function testInsertAndContains() public {
        assertFalse(contains(tree, 100));

        insert(tree, 100);
        assertTrue(contains(tree, 100));
    }

    function testInsertMultiple() public {
        insert(tree, 50);
        insert(tree, 30);
        insert(tree, 70);
        insert(tree, 20);
        insert(tree, 40);

        assertTrue(contains(tree, 50));
        assertTrue(contains(tree, 30));
        assertTrue(contains(tree, 70));
        assertTrue(contains(tree, 20));
        assertTrue(contains(tree, 40));
    }

    function testInsertRevertDuplicateKey() public {
        insert(tree, 100);

        vm.expectRevert("Key already exists");
        insert(tree, 100);
    }

    function testInsertRevertZeroKey() public {
        vm.expectRevert("Key cannot be 0");
        insert(tree, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        GET MIN/MAX TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetMinMax() public {
        insert(tree, 50);
        insert(tree, 30);
        insert(tree, 70);
        insert(tree, 20);
        insert(tree, 90);

        uint256 minKey = getMin(tree);
        assertEq(minKey, 20);

        uint256 maxKey = getMax(tree);
        assertEq(maxKey, 90);
    }

    function testGetMinMaxSingleElement() public {
        insert(tree, 100);

        assertEq(getMin(tree), 100);
        assertEq(getMax(tree), 100);
    }

    function testGetMinRevertEmptyTree() public {
        // getMin now returns 0 for empty tree instead of reverting
        uint256 minKey = getMin(tree);
        assertEq(minKey, 0, "Empty tree should return 0");
    }

    function testGetMaxRevertEmptyTree() public {
        // getMax now returns 0 for empty tree instead of reverting
        uint256 maxKey = getMax(tree);
        assertEq(maxKey, 0, "Empty tree should return 0");
    }

    /*//////////////////////////////////////////////////////////////
                        GET RANK TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetRank() public {
        // Insert keys: 20, 30, 40, 50, 70
        insert(tree, 50);
        insert(tree, 30);
        insert(tree, 70);
        insert(tree, 20);
        insert(tree, 40);

        assertEq(getRank(tree, 20), 1); // smallest
        assertEq(getRank(tree, 30), 2);
        assertEq(getRank(tree, 40), 3);
        assertEq(getRank(tree, 50), 4);
        assertEq(getRank(tree, 70), 5); // largest
    }

    function testGetRankAfterRemoval() public {
        // Insert keys: 20, 30, 40, 50, 70
        insert(tree, 50);
        insert(tree, 30);
        insert(tree, 70);
        insert(tree, 20);
        insert(tree, 40);

        // Remove 30
        remove(tree, 30);

        // New order: 20, 40, 50, 70
        assertEq(getRank(tree, 20), 1);
        assertEq(getRank(tree, 40), 2);
        assertEq(getRank(tree, 50), 3);
        assertEq(getRank(tree, 70), 4);
    }

    function testGetRankRevertNotFound() public {
        insert(tree, 100);

        vm.expectRevert("Key not found");
        getRank(tree, 999);
    }

    /*//////////////////////////////////////////////////////////////
                        REMOVE TESTS
    //////////////////////////////////////////////////////////////*/

    function testRemove() public {
        insert(tree, 50);
        insert(tree, 30);
        insert(tree, 70);
        insert(tree, 20);
        insert(tree, 40);

        assertTrue(contains(tree, 30));

        remove(tree, 30);

        assertFalse(contains(tree, 30));
        assertTrue(contains(tree, 50));
        assertTrue(contains(tree, 70));
        assertTrue(contains(tree, 20));
        assertTrue(contains(tree, 40));
    }

    function testRemoveAndReinsert() public {
        insert(tree, 50);
        insert(tree, 30);

        remove(tree, 30);
        assertFalse(contains(tree, 30));

        insert(tree, 30);
        assertTrue(contains(tree, 30));
    }

    function testRemoveAllElements() public {
        insert(tree, 50);
        insert(tree, 30);
        insert(tree, 70);

        remove(tree, 50);
        remove(tree, 30);
        remove(tree, 70);

        assertTrue(isEmpty(tree));
    }

    function testRemoveRevertNotFound() public {
        vm.expectRevert("Key not found");
        remove(tree, 999);
    }

    /*//////////////////////////////////////////////////////////////
                        EMPTY TREE TESTS
    //////////////////////////////////////////////////////////////*/

    function testEmptyTree() public {
        assertTrue(isEmpty(tree));
    }

    function testEmptyTreeAfterInsert() public {
        assertTrue(isEmpty(tree));

        insert(tree, 100);
        assertFalse(isEmpty(tree));
    }

    function testEmptyTreeAfterRemoveAll() public {
        insert(tree, 100);
        insert(tree, 200);

        remove(tree, 100);
        remove(tree, 200);

        assertTrue(isEmpty(tree));
    }

    /*//////////////////////////////////////////////////////////////
                        STRESS TESTS
    //////////////////////////////////////////////////////////////*/

    function testStressInsert() public {
        // Insert 100 elements
        for (uint256 i = 1; i <= 100; i++) {
            insert(tree, i * 1000);
        }

        // Verify first and last
        uint256 minKey = getMin(tree);
        assertEq(minKey, 1000);

        uint256 maxKey = getMax(tree);
        assertEq(maxKey, 100000);

        // Verify middle element rank
        assertEq(getRank(tree, 50000), 50);
    }

    function testStressRemove() public {
        // Insert 20 elements
        for (uint256 i = 1; i <= 20; i++) {
            insert(tree, i * 10);
        }

        // Remove every other element
        for (uint256 i = 1; i <= 10; i++) {
            remove(tree, i * 20);
        }

        // Verify remaining elements
        for (uint256 i = 1; i <= 10; i++) {
            assertTrue(contains(tree, (i * 2 - 1) * 10));
            assertFalse(contains(tree, i * 20));
        }

        assertEq(getMin(tree), 10);
        assertEq(getMax(tree), 190);
    }

    function testStressRankAfterMixedOps() public {
        // Insert in random order
        uint256[] memory keys = new uint256[](10);
        keys[0] = 50; keys[1] = 25; keys[2] = 75; keys[3] = 10; keys[4] = 30;
        keys[5] = 60; keys[6] = 90; keys[7] = 5; keys[8] = 35; keys[9] = 85;

        for (uint256 i = 0; i < keys.length; i++) {
            insert(tree, keys[i]);
        }

        // Remove some elements
        remove(tree, 25);
        remove(tree, 75);

        // Remaining sorted: 5, 10, 30, 35, 50, 60, 85, 90
        assertEq(getRank(tree, 5), 1);
        assertEq(getRank(tree, 10), 2);
        assertEq(getRank(tree, 30), 3);
        assertEq(getRank(tree, 35), 4);
        assertEq(getRank(tree, 50), 5);
        assertEq(getRank(tree, 60), 6);
        assertEq(getRank(tree, 85), 7);
        assertEq(getRank(tree, 90), 8);
    }

    /*//////////////////////////////////////////////////////////////
                        LIQUIDATION SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function testLiquidationQueueScenario() public {
        // Simulate liquidation prices for positions
        // Lower price = closer to liquidation = higher priority
        insert(tree, 45000e6); // Position liquidates at $45k
        insert(tree, 47000e6); // Position liquidates at $47k
        insert(tree, 43000e6); // Position liquidates at $43k (most at risk)
        insert(tree, 50000e6); // Position liquidates at $50k
        insert(tree, 44000e6); // Position liquidates at $44k

        // Find most at-risk position
        uint256 minPrice = getMin(tree);
        assertEq(minPrice, 43000e6);

        // Get rank of 44k position (second most at-risk)
        uint256 rank = getRank(tree, 44000e6);
        assertEq(rank, 2);

        // After liquidating the most at-risk position
        remove(tree, 43000e6);

        // New most at-risk
        assertEq(getMin(tree), 44000e6);
        assertEq(getRank(tree, 44000e6), 1);
    }

    function testLiquidationBatchRemoval() public {
        // Insert 10 positions with different liquidation prices
        for (uint256 i = 1; i <= 10; i++) {
            insert(tree, 40000e6 + i * 1000e6);
        }

        // Liquidate first 3 most at-risk positions
        for (uint256 i = 0; i < 3; i++) {
            uint256 minKey = getMin(tree);
            remove(tree, minKey);
        }

        // Verify remaining positions
        assertEq(getMin(tree), 44000e6);
        assertEq(getRank(tree, 44000e6), 1);
        assertEq(getRank(tree, 45000e6), 2);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testSingleElement() public {
        insert(tree, 100);

        assertFalse(isEmpty(tree));
        assertEq(getRank(tree, 100), 1);
        assertEq(getMin(tree), 100);
        assertEq(getMax(tree), 100);

        remove(tree, 100);
        assertTrue(isEmpty(tree));
    }

    function testTwoElements() public {
        insert(tree, 100);
        insert(tree, 200);

        assertEq(getRank(tree, 100), 1);
        assertEq(getRank(tree, 200), 2);
        assertEq(getMin(tree), 100);
        assertEq(getMax(tree), 200);
    }

    function testRemoveRoot() public {
        insert(tree, 50);
        insert(tree, 30);
        insert(tree, 70);

        // Remove root
        remove(tree, 50);

        // Tree should still be valid
        assertFalse(contains(tree, 50));
        assertTrue(contains(tree, 30));
        assertTrue(contains(tree, 70));
        assertEq(getMin(tree), 30);
        assertEq(getMax(tree), 70);
    }

    function testSequentialInsert() public {
        // Insert in ascending order (stress test for tree balancing)
        for (uint256 i = 1; i <= 10; i++) {
            insert(tree, i);
        }

        // Verify all elements and their ranks
        for (uint256 i = 1; i <= 10; i++) {
            assertTrue(contains(tree, i));
            assertEq(getRank(tree, i), i);
        }

        assertEq(getMin(tree), 1);
        assertEq(getMax(tree), 10);
    }

    function testReverseSequentialInsert() public {
        // Insert in descending order (stress test for tree balancing)
        for (uint256 i = 10; i >= 1; i--) {
            insert(tree, i);
        }

        // Verify all elements and their ranks
        for (uint256 i = 1; i <= 10; i++) {
            assertTrue(contains(tree, i));
            assertEq(getRank(tree, i), i);
        }

        assertEq(getMin(tree), 1);
        assertEq(getMax(tree), 10);
    }

    function testLargeKeys() public {
        uint256 key1 = type(uint256).max - 2;
        uint256 key2 = type(uint256).max - 1;
        uint256 key3 = type(uint256).max - 3;

        insert(tree, key1);
        insert(tree, key2);
        insert(tree, key3);

        assertEq(getMin(tree), key3);
        assertEq(getMax(tree), key2);
        assertEq(getRank(tree, key3), 1);
        assertEq(getRank(tree, key1), 2);
        assertEq(getRank(tree, key2), 3);
    }

    /*//////////////////////////////////////////////////////////////
                    STRESS TEST: 2000 NODES
    //////////////////////////////////////////////////////////////*/

    function testStress2000Nodes_Insert() public {
        // Insert 2000 nodes
        for (uint256 i = 1; i <= 1000; i++) {
            insert(tree, i * 1000);
        }

        for (uint256 i = 1; i <= 1000; i++) {
            insert(tree, i * 1000 + 500);
        }

        // Verify tree properties
        assertEq(getMin(tree), 1000);
        assertEq(getMax(tree), 1000500);

        // Verify some ranks
        assertEq(getRank(tree, 1000), 1);
        assertEq(getRank(tree, 500500), 1000);
        assertEq(getRank(tree, 1000500), 2000);
    }

    function testStress2000Nodes_InsertGas() public {
        // Measure gas for inserting at different tree sizes
        uint256 gasStart;
        uint256 gasUsed;

        // Insert first 1000 nodes
        for (uint256 i = 1; i <= 1000; i++) {
            insert(tree, i * 1000);
        }

        // Measure gas for insert at 1000 nodes
        gasStart = gasleft();
        insert(tree, 1001000);
        gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas for insert at 1000 nodes", gasUsed);

        // Insert another 999 nodes (1001 total now, +999 = 2000)
        for (uint256 i = 1002; i <= 2000; i++) {
            insert(tree, i * 1000);
        }

        // Measure gas for insert at 2000 nodes
        gasStart = gasleft();
        insert(tree, 2001000);
        gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas for insert at 2000 nodes", gasUsed);

        // Verify tree is valid
        assertEq(getRank(tree, 1001000), 1001);
        assertEq(getRank(tree, 2001000), 2001);
    }

    function testStress2000Nodes_RemoveGas() public {
        // Insert 2000 nodes
        for (uint256 i = 1; i <= 2000; i++) {
            insert(tree, i * 1000);
        }

        uint256 gasStart;
        uint256 gasUsed;

        // Measure gas for remove at 2000 nodes
        gasStart = gasleft();
        remove(tree, 1000 * 1000); // Remove element at rank 1000
        gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas for remove at 2000 nodes", gasUsed);

        // Remove 999 more nodes (rank 2-1000, keeping rank 1)
        for (uint256 i = 2; i <= 1000; i++) {
            if (i != 1000) { // Skip the one we already removed
                remove(tree, i * 1000);
            }
        }

        // Measure gas for remove at ~1000 nodes
        gasStart = gasleft();
        remove(tree, 1001 * 1000);
        gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas for remove at 1000 nodes", gasUsed);

        // Verify tree is still valid
        assertTrue(contains(tree, 1002 * 1000));
        assertFalse(contains(tree, 1000 * 1000));
    }

    function testStress2000Nodes_GetRankGas() public {
        // Insert 2000 nodes
        for (uint256 i = 1; i <= 2000; i++) {
            insert(tree, i * 1000);
        }

        uint256 gasStart;
        uint256 gasUsed;

        // Measure gas for getRank at different positions
        gasStart = gasleft();
        uint256 rank1 = getRank(tree, 1000); // First element
        gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas for getRank (first element)", gasUsed);
        assertEq(rank1, 1);

        gasStart = gasleft();
        uint256 rank1000 = getRank(tree, 1000000); // Middle element
        gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas for getRank (middle element)", gasUsed);
        assertEq(rank1000, 1000);

        gasStart = gasleft();
        uint256 rank2000 = getRank(tree, 2000000); // Last element
        gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas for getRank (last element)", gasUsed);
        assertEq(rank2000, 2000);
    }

    function testStress2000Nodes_MixedOperations() public {
        // Insert 2000 nodes
        for (uint256 i = 1; i <= 2000; i++) {
            insert(tree, i * 1000);
        }

        // Remove every 5th element (400 removals)
        for (uint256 i = 5; i <= 2000; i += 5) {
            remove(tree, i * 1000);
        }

        // Verify tree integrity
        assertEq(getMin(tree), 1000);
        assertEq(getMax(tree), 1999000);

        // Verify some elements are removed
        assertFalse(contains(tree, 5000));
        assertFalse(contains(tree, 10000));

        // Verify some elements still exist
        assertTrue(contains(tree, 1000));
        assertTrue(contains(tree, 2000));
        assertTrue(contains(tree, 1999000));

        // Verify rank calculations are still correct
        uint256 expectedRank = 1;
        for (uint256 i = 1; i <= 2000; i++) {
            if (i % 5 != 0) {
                assertEq(getRank(tree, i * 1000), expectedRank);
                expectedRank++;
            }
        }
    }

    function testStress2000Nodes_Liquidation() public {
        // Simulate 2000 positions with liquidation prices
        // Lower price = higher risk
        for (uint256 i = 1; i <= 2000; i++) {
            insert(tree, 40000e6 + i * 1000e6); // Prices from $40k to $2.04M
        }

        uint256 gasStart;
        uint256 gasUsed;

        // Measure gas for finding most at-risk position
        gasStart = gasleft();
        uint256 mostAtRisk = getMin(tree);
        gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas for getMin (2000 nodes)", gasUsed);
        assertEq(mostAtRisk, 41000e6); // 40000e6 + 1*1000e6 = 41000e6

        // Simulate batch liquidation of 100 positions
        gasStart = gasleft();
        for (uint256 i = 0; i < 100; i++) {
            uint256 minKey = getMin(tree);
            remove(tree, minKey);
        }
        gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas for batch liquidating 100 positions", gasUsed);
        emit log_named_uint("Average gas per liquidation", gasUsed / 100);

        // Verify remaining positions
        assertEq(getMin(tree), 141000e6); // 40000e6 + 101*1000e6 = 141000e6

        // Verify rank of a middle position
        // After removing 100, element 1000 becomes rank 900
        uint256 middleRank = getRank(tree, 1040000e6); // i=1000, now at rank 900
        assertTrue(middleRank > 800 && middleRank < 1000);
    }
}
