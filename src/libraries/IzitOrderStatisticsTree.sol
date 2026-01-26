// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IzitOrderStatisticsTree
 * @notice Enhanced Red-Black Tree with Order Statistics for efficient ranking and liquidation queue
 * @dev Supports O(log n) operations:
 *      - insert/remove: O(log n)
 *      - getRank: O(log n) - Get position rank in sorted order
 *      - getKthSmallest: O(log n) - Get k-th smallest element
 *      - countLessThan: O(log n) - Count elements less than threshold
 *
 * Perfect for liquidation queues where we need:
 * - Know position's risk ranking (e.g., "58th most at-risk out of 2000")
 * - Batch liquidate first N positions
 * - Estimate liquidation pressure at price levels
 */
library IzitOrderStatisticsTree {

    uint256 private constant NIL = 0;
    bool private constant RED = true;
    bool private constant BLACK = false;

    struct Node {
        uint256 key;           // Liquidation price (or any sortable key)
        uint256 value;         // Position ID (OrderId)
        uint256 parent;
        uint256 left;
        uint256 right;
        uint256 size;          // Size of subtree rooted at this node
        bool isRed;
    }

    struct Tree {
        uint256 root;
        uint256 nodeCount;
        mapping(uint256 => Node) nodes;
        mapping(uint256 => uint256) keyToNodeId;  // key => nodeId
    }

    // Events for debugging
    event NodeInserted(uint256 key, uint256 value, uint256 nodeId);
    event NodeRemoved(uint256 key, uint256 nodeId);

    /*//////////////////////////////////////////////////////////////
                            CORE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Insert a new key-value pair
     * @param tree The tree storage
     * @param key The key to insert (e.g., liquidation price)
     * @param value The value to store (e.g., position ID)
     */
    function insert(Tree storage tree, uint256 key, uint256 value) internal {
        require(key != 0, "Key cannot be 0");
        require(!contains(tree, key), "Key already exists");

        uint256 nodeId = ++tree.nodeCount;
        tree.keyToNodeId[key] = nodeId;

        // Standard BST insert
        uint256 parent = NIL;
        uint256 current = tree.root;

        while (current != NIL) {
            parent = current;
            tree.nodes[current].size++;  // Update size along the path

            if (key < tree.nodes[current].key) {
                current = tree.nodes[current].left;
            } else {
                current = tree.nodes[current].right;
            }
        }

        // Create new node
        tree.nodes[nodeId] = Node({
            key: key,
            value: value,
            parent: parent,
            left: NIL,
            right: NIL,
            size: 1,
            isRed: true  // New nodes are red
        });

        if (parent == NIL) {
            tree.root = nodeId;
        } else if (key < tree.nodes[parent].key) {
            tree.nodes[parent].left = nodeId;
        } else {
            tree.nodes[parent].right = nodeId;
        }

        // Fix Red-Black properties
        insertFixup(tree, nodeId);

        emit NodeInserted(key, value, nodeId);
    }

    /**
     * @notice Remove a key from the tree
     * @param tree The tree storage
     * @param key The key to remove
     */
    function remove(Tree storage tree, uint256 key) internal {
        require(contains(tree, key), "Key not found");

        uint256 nodeId = tree.keyToNodeId[key];
        delete tree.keyToNodeId[key];

        uint256 toDelete = nodeId;
        uint256 replacement;
        bool originalColor = tree.nodes[toDelete].isRed;

        if (tree.nodes[nodeId].left == NIL) {
            replacement = tree.nodes[nodeId].right;
            transplant(tree, nodeId, tree.nodes[nodeId].right);
        } else if (tree.nodes[nodeId].right == NIL) {
            replacement = tree.nodes[nodeId].left;
            transplant(tree, nodeId, tree.nodes[nodeId].left);
        } else {
            // Node has two children, find successor
            toDelete = minimum(tree, tree.nodes[nodeId].right);
            originalColor = tree.nodes[toDelete].isRed;
            replacement = tree.nodes[toDelete].right;

            if (tree.nodes[toDelete].parent == nodeId) {
                if (replacement != NIL) {
                    tree.nodes[replacement].parent = toDelete;
                }
            } else {
                transplant(tree, toDelete, tree.nodes[toDelete].right);
                tree.nodes[toDelete].right = tree.nodes[nodeId].right;
                tree.nodes[tree.nodes[toDelete].right].parent = toDelete;
            }

            transplant(tree, nodeId, toDelete);
            tree.nodes[toDelete].left = tree.nodes[nodeId].left;
            tree.nodes[tree.nodes[toDelete].left].parent = toDelete;
            tree.nodes[toDelete].isRed = tree.nodes[nodeId].isRed;
            tree.nodes[toDelete].size = tree.nodes[nodeId].size;
        }

        // Update sizes along the path
        uint256 current = tree.nodes[toDelete].parent;
        while (current != NIL) {
            updateSize(tree, current);
            current = tree.nodes[current].parent;
        }

        // Fix Red-Black properties if we removed a black node
        if (!originalColor && replacement != NIL) {
            deleteFixup(tree, replacement);
        }

        emit NodeRemoved(key, nodeId);
    }

    /*//////////////////////////////////////////////////////////////
                        ORDER STATISTICS QUERIES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the rank of a key (1-indexed, 1 = smallest)
     * @param tree The tree storage
     * @param key The key to find rank for
     * @return rank The rank (1 = smallest, 2 = second smallest, etc.)
     */
    function getRank(Tree storage tree, uint256 key) internal view returns (uint256 rank) {
        require(contains(tree, key), "Key not found");

        uint256 nodeId = tree.keyToNodeId[key];
        rank = getSize(tree, tree.nodes[nodeId].left) + 1;

        uint256 current = nodeId;
        while (current != tree.root) {
            uint256 parent = tree.nodes[current].parent;
            if (current == tree.nodes[parent].right) {
                rank += getSize(tree, tree.nodes[parent].left) + 1;
            }
            current = parent;
        }
    }

    /**
     * @notice Get the k-th smallest key (1-indexed)
     * @param tree The tree storage
     * @param k The rank to find (1 = smallest)
     * @return key The k-th smallest key
     * @return value The corresponding value
     */
    function getKthSmallest(Tree storage tree, uint256 k)
        internal
        view
        returns (uint256 key, uint256 value)
    {
        require(k > 0 && k <= getSize(tree, tree.root), "k out of range");

        uint256 nodeId = selectNode(tree, tree.root, k);
        key = tree.nodes[nodeId].key;
        value = tree.nodes[nodeId].value;
    }

    /**
     * @notice Count how many keys are less than the given threshold
     * @param tree The tree storage
     * @param threshold The threshold value
     * @return count Number of keys less than threshold
     */
    function countLessThan(Tree storage tree, uint256 threshold)
        internal
        view
        returns (uint256 count)
    {
        return countLessThanRecursive(tree, tree.root, threshold);
    }

    /**
     * @notice Get all keys less than threshold (for batch liquidation)
     * @param tree The tree storage
     * @param threshold The threshold value
     * @param maxResults Maximum number of results to return
     * @return keys Array of keys less than threshold
     * @return values Array of corresponding values
     */
    function getKeysLessThan(Tree storage tree, uint256 threshold, uint256 maxResults)
        internal
        view
        returns (uint256[] memory keys, uint256[] memory values)
    {
        uint256 count = countLessThan(tree, threshold);
        if (count > maxResults) count = maxResults;

        keys = new uint256[](count);
        values = new uint256[](count);

        if (count > 0) {
            collectKeysLessThan(tree, tree.root, threshold, keys, values, 0, maxResults);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            BASIC QUERIES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if tree contains a key
     */
    function contains(Tree storage tree, uint256 key) internal view returns (bool) {
        return tree.keyToNodeId[key] != NIL;
    }

    /**
     * @notice Get value for a key
     */
    function getValue(Tree storage tree, uint256 key) internal view returns (uint256) {
        require(contains(tree, key), "Key not found");
        return tree.nodes[tree.keyToNodeId[key]].value;
    }

    /**
     * @notice Get minimum key in tree
     */
    function getMin(Tree storage tree) internal view returns (uint256 key, uint256 value) {
        require(tree.root != NIL, "Tree is empty");
        uint256 nodeId = minimum(tree, tree.root);
        key = tree.nodes[nodeId].key;
        value = tree.nodes[nodeId].value;
    }

    /**
     * @notice Get maximum key in tree
     */
    function getMax(Tree storage tree) internal view returns (uint256 key, uint256 value) {
        require(tree.root != NIL, "Tree is empty");
        uint256 nodeId = maximum(tree, tree.root);
        key = tree.nodes[nodeId].key;
        value = tree.nodes[nodeId].value;
    }

    /**
     * @notice Get total number of nodes in tree
     */
    function size(Tree storage tree) internal view returns (uint256) {
        return getSize(tree, tree.root);
    }

    /**
     * @notice Check if tree is empty
     */
    function isEmpty(Tree storage tree) internal view returns (bool) {
        return tree.root == NIL;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getSize(Tree storage tree, uint256 nodeId) private view returns (uint256) {
        return nodeId == NIL ? 0 : tree.nodes[nodeId].size;
    }

    function updateSize(Tree storage tree, uint256 nodeId) private {
        if (nodeId != NIL) {
            tree.nodes[nodeId].size = 1 +
                getSize(tree, tree.nodes[nodeId].left) +
                getSize(tree, tree.nodes[nodeId].right);
        }
    }

    function minimum(Tree storage tree, uint256 nodeId) private view returns (uint256) {
        while (tree.nodes[nodeId].left != NIL) {
            nodeId = tree.nodes[nodeId].left;
        }
        return nodeId;
    }

    function maximum(Tree storage tree, uint256 nodeId) private view returns (uint256) {
        while (tree.nodes[nodeId].right != NIL) {
            nodeId = tree.nodes[nodeId].right;
        }
        return nodeId;
    }

    function selectNode(Tree storage tree, uint256 nodeId, uint256 k)
        private
        view
        returns (uint256)
    {
        uint256 leftSize = getSize(tree, tree.nodes[nodeId].left);

        if (k == leftSize + 1) {
            return nodeId;
        } else if (k <= leftSize) {
            return selectNode(tree, tree.nodes[nodeId].left, k);
        } else {
            return selectNode(tree, tree.nodes[nodeId].right, k - leftSize - 1);
        }
    }

    function countLessThanRecursive(Tree storage tree, uint256 nodeId, uint256 threshold)
        private
        view
        returns (uint256)
    {
        if (nodeId == NIL) return 0;

        if (tree.nodes[nodeId].key >= threshold) {
            // All nodes in right subtree are >= threshold
            return countLessThanRecursive(tree, tree.nodes[nodeId].left, threshold);
        } else {
            // This node and entire left subtree are < threshold
            return 1 +
                getSize(tree, tree.nodes[nodeId].left) +
                countLessThanRecursive(tree, tree.nodes[nodeId].right, threshold);
        }
    }

    function collectKeysLessThan(
        Tree storage tree,
        uint256 nodeId,
        uint256 threshold,
        uint256[] memory keys,
        uint256[] memory values,
        uint256 index,
        uint256 maxResults
    ) private view returns (uint256) {
        if (nodeId == NIL || index >= maxResults) return index;

        // In-order traversal to collect keys in sorted order
        if (tree.nodes[nodeId].key < threshold) {
            // Collect left subtree
            index = collectKeysLessThan(tree, tree.nodes[nodeId].left, threshold, keys, values, index, maxResults);

            // Collect current node
            if (index < maxResults) {
                keys[index] = tree.nodes[nodeId].key;
                values[index] = tree.nodes[nodeId].value;
                index++;
            }

            // Collect right subtree
            index = collectKeysLessThan(tree, tree.nodes[nodeId].right, threshold, keys, values, index, maxResults);
        } else {
            // Only check left subtree
            index = collectKeysLessThan(tree, tree.nodes[nodeId].left, threshold, keys, values, index, maxResults);
        }

        return index;
    }

    /*//////////////////////////////////////////////////////////////
                        RED-BLACK TREE MAINTENANCE
    //////////////////////////////////////////////////////////////*/

    function rotateLeft(Tree storage tree, uint256 nodeId) private {
        uint256 right = tree.nodes[nodeId].right;

        tree.nodes[nodeId].right = tree.nodes[right].left;
        if (tree.nodes[right].left != NIL) {
            tree.nodes[tree.nodes[right].left].parent = nodeId;
        }

        tree.nodes[right].parent = tree.nodes[nodeId].parent;
        if (tree.nodes[nodeId].parent == NIL) {
            tree.root = right;
        } else if (nodeId == tree.nodes[tree.nodes[nodeId].parent].left) {
            tree.nodes[tree.nodes[nodeId].parent].left = right;
        } else {
            tree.nodes[tree.nodes[nodeId].parent].right = right;
        }

        tree.nodes[right].left = nodeId;
        tree.nodes[nodeId].parent = right;

        // Update sizes
        updateSize(tree, nodeId);
        updateSize(tree, right);
    }

    function rotateRight(Tree storage tree, uint256 nodeId) private {
        uint256 left = tree.nodes[nodeId].left;

        tree.nodes[nodeId].left = tree.nodes[left].right;
        if (tree.nodes[left].right != NIL) {
            tree.nodes[tree.nodes[left].right].parent = nodeId;
        }

        tree.nodes[left].parent = tree.nodes[nodeId].parent;
        if (tree.nodes[nodeId].parent == NIL) {
            tree.root = left;
        } else if (nodeId == tree.nodes[tree.nodes[nodeId].parent].right) {
            tree.nodes[tree.nodes[nodeId].parent].right = left;
        } else {
            tree.nodes[tree.nodes[nodeId].parent].left = left;
        }

        tree.nodes[left].right = nodeId;
        tree.nodes[nodeId].parent = left;

        // Update sizes
        updateSize(tree, nodeId);
        updateSize(tree, left);
    }

    function insertFixup(Tree storage tree, uint256 nodeId) private {
        while (tree.nodes[tree.nodes[nodeId].parent].isRed) {
            uint256 parent = tree.nodes[nodeId].parent;
            uint256 grandparent = tree.nodes[parent].parent;

            if (parent == tree.nodes[grandparent].left) {
                uint256 uncle = tree.nodes[grandparent].right;

                if (uncle != NIL && tree.nodes[uncle].isRed) {
                    // Case 1: Uncle is red
                    tree.nodes[parent].isRed = BLACK;
                    tree.nodes[uncle].isRed = BLACK;
                    tree.nodes[grandparent].isRed = RED;
                    nodeId = grandparent;
                } else {
                    if (nodeId == tree.nodes[parent].right) {
                        // Case 2: Node is right child
                        nodeId = parent;
                        rotateLeft(tree, nodeId);
                        parent = tree.nodes[nodeId].parent;
                        grandparent = tree.nodes[parent].parent;
                    }
                    // Case 3: Node is left child
                    tree.nodes[parent].isRed = BLACK;
                    tree.nodes[grandparent].isRed = RED;
                    rotateRight(tree, grandparent);
                }
            } else {
                uint256 uncle = tree.nodes[grandparent].left;

                if (uncle != NIL && tree.nodes[uncle].isRed) {
                    tree.nodes[parent].isRed = BLACK;
                    tree.nodes[uncle].isRed = BLACK;
                    tree.nodes[grandparent].isRed = RED;
                    nodeId = grandparent;
                } else {
                    if (nodeId == tree.nodes[parent].left) {
                        nodeId = parent;
                        rotateRight(tree, nodeId);
                        parent = tree.nodes[nodeId].parent;
                        grandparent = tree.nodes[parent].parent;
                    }
                    tree.nodes[parent].isRed = BLACK;
                    tree.nodes[grandparent].isRed = RED;
                    rotateLeft(tree, grandparent);
                }
            }
        }
        tree.nodes[tree.root].isRed = BLACK;
    }

    function deleteFixup(Tree storage tree, uint256 nodeId) private {
        while (nodeId != tree.root && !tree.nodes[nodeId].isRed) {
            uint256 parent = tree.nodes[nodeId].parent;

            if (nodeId == tree.nodes[parent].left) {
                uint256 sibling = tree.nodes[parent].right;

                if (tree.nodes[sibling].isRed) {
                    tree.nodes[sibling].isRed = BLACK;
                    tree.nodes[parent].isRed = RED;
                    rotateLeft(tree, parent);
                    sibling = tree.nodes[parent].right;
                }

                if (!tree.nodes[tree.nodes[sibling].left].isRed &&
                    !tree.nodes[tree.nodes[sibling].right].isRed) {
                    tree.nodes[sibling].isRed = RED;
                    nodeId = parent;
                } else {
                    if (!tree.nodes[tree.nodes[sibling].right].isRed) {
                        tree.nodes[tree.nodes[sibling].left].isRed = BLACK;
                        tree.nodes[sibling].isRed = RED;
                        rotateRight(tree, sibling);
                        sibling = tree.nodes[parent].right;
                    }
                    tree.nodes[sibling].isRed = tree.nodes[parent].isRed;
                    tree.nodes[parent].isRed = BLACK;
                    tree.nodes[tree.nodes[sibling].right].isRed = BLACK;
                    rotateLeft(tree, parent);
                    nodeId = tree.root;
                }
            } else {
                uint256 sibling = tree.nodes[parent].left;

                if (tree.nodes[sibling].isRed) {
                    tree.nodes[sibling].isRed = BLACK;
                    tree.nodes[parent].isRed = RED;
                    rotateRight(tree, parent);
                    sibling = tree.nodes[parent].left;
                }

                if (!tree.nodes[tree.nodes[sibling].right].isRed &&
                    !tree.nodes[tree.nodes[sibling].left].isRed) {
                    tree.nodes[sibling].isRed = RED;
                    nodeId = parent;
                } else {
                    if (!tree.nodes[tree.nodes[sibling].left].isRed) {
                        tree.nodes[tree.nodes[sibling].right].isRed = BLACK;
                        tree.nodes[sibling].isRed = RED;
                        rotateLeft(tree, sibling);
                        sibling = tree.nodes[parent].left;
                    }
                    tree.nodes[sibling].isRed = tree.nodes[parent].isRed;
                    tree.nodes[parent].isRed = BLACK;
                    tree.nodes[tree.nodes[sibling].left].isRed = BLACK;
                    rotateRight(tree, parent);
                    nodeId = tree.root;
                }
            }
        }
        tree.nodes[nodeId].isRed = BLACK;
    }

    function transplant(Tree storage tree, uint256 target, uint256 replacement) private {
        if (tree.nodes[target].parent == NIL) {
            tree.root = replacement;
        } else if (target == tree.nodes[tree.nodes[target].parent].left) {
            tree.nodes[tree.nodes[target].parent].left = replacement;
        } else {
            tree.nodes[tree.nodes[target].parent].right = replacement;
        }

        if (replacement != NIL) {
            tree.nodes[replacement].parent = tree.nodes[target].parent;
        }
    }
}
