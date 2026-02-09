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
abstract contract IzitOSTreeMinimum {

    uint256 private constant NIL = 0;
    bool private constant RED = true;
    bool private constant BLACK = false;

    struct Node {
        uint256 key;           // Slot 0: Key pointer (Position ID/OrderId) - must be uint256
        uint128 parent;        // Slot 1 high: Parent node ID (max 2^128 nodes)
        uint128 left;          // Slot 1 low: Left child node ID
        uint128 right;         // Slot 2 high: Right child node ID
        uint64 size;           // Slot 2 mid: Size of subtree (max 2^64 nodes)
        bool isRed;            // Slot 2 low: Red-Black color (8 bits)
    }
    // Storage: 3 slots (was 6) = 50% reduction!

    struct Tree {
        uint128 root;          // Root node ID
        uint128 nodeCount;     // Total nodes created
        mapping(uint256 => Node) nodes;
        mapping(uint256 => uint256) keyToNodeId;  // key => nodeId
    }
    // Note: root and nodeCount are packed into 1 slot

    // Events for debugging
    event NodeInserted(uint256 key, uint256 nodeId);
    event NodeRemoved(uint256 key, uint256 nodeId);

    error KeyNotFound();
    error EmptyTree();

    /*//////////////////////////////////////////////////////////////
                            CORE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function _less(uint256 ptr_a, uint256 ptr_b)
        internal
        virtual
    returns (bool);

    /**
     * @notice Insert a new key-value pair
     * @param tree The tree storage
     * @param key The key to insert (e.g., position ID)
     */
    function insert(Tree storage tree, uint256 key) internal {
        require(key != 0, "Key cannot be 0");
        require(!contains(tree, key), "Key already exists");

        uint128 nodeId = ++tree.nodeCount;
        tree.keyToNodeId[key] = nodeId;

        // Standard BST insert
        uint128 parent = uint128(NIL);
        uint128 current = tree.root;

        while (current != NIL) {
            parent = current;
            tree.nodes[current].size++;  // Update size along the path

            if ( _less(key,tree.nodes[current].key) ) {
                current = tree.nodes[current].left;
            } else {
                current = tree.nodes[current].right;
            }
        }

        // Create new node
        tree.nodes[nodeId] = Node({
            key: key,
            parent: parent,
            left: uint128(NIL),
            right: uint128(NIL),
            size: 1,
            isRed: true  // New nodes are red
        });

        if (parent == NIL) {
            tree.root = nodeId;
        } else if (_less(key,tree.nodes[parent].key)) {
            tree.nodes[parent].left = nodeId;
        } else {
            tree.nodes[parent].right = nodeId;
        }

        // Fix Red-Black properties
        insertFixup(tree, nodeId);

        emit NodeInserted(key, nodeId);
    }

    /**
     * @notice Remove a key from the tree
     * @param tree The tree storage
     * @param key The key to remove
     */
    function remove(Tree storage tree, uint256 key) internal {
        if(!contains(tree, key)) revert KeyNotFound();

        uint128 nodeId = uint128(tree.keyToNodeId[key]);
        delete tree.keyToNodeId[key];

        uint128 toDelete = nodeId;
        uint128 replacement;
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
                // Decrement sizes along path from toDelete to nodeId before moving toDelete
                uint128 temp = tree.nodes[toDelete].parent;
                while (temp != nodeId) {
                    tree.nodes[temp].size--;
                    temp = tree.nodes[temp].parent;
                }

                transplant(tree, toDelete, tree.nodes[toDelete].right);
                tree.nodes[toDelete].right = tree.nodes[nodeId].right;
                tree.nodes[tree.nodes[toDelete].right].parent = toDelete;
            }

            transplant(tree, nodeId, toDelete);
            tree.nodes[toDelete].left = tree.nodes[nodeId].left;
            tree.nodes[tree.nodes[toDelete].left].parent = toDelete;
            tree.nodes[toDelete].isRed = tree.nodes[nodeId].isRed;
            // Don't copy size - let updateSize recalculate it correctly
        }

        // Update sizes along the path, starting from toDelete itself
        uint128 current = toDelete;
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
        if(!contains(tree, key)) revert KeyNotFound();

        uint128 nodeId = uint128(tree.keyToNodeId[key]);
        rank = getSize(tree, tree.nodes[nodeId].left) + 1;

        uint128 current = nodeId;
        while (current != tree.root) {
            uint128 parent = tree.nodes[current].parent;
            if (current == tree.nodes[parent].right) {
                rank += getSize(tree, tree.nodes[parent].left) + 1;
            }
            current = parent;
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
     * @notice Get minimum key in tree
     */
    function getMin(Tree storage tree) internal view returns (uint256 key) {
        if(tree.root == NIL) revert EmptyTree();
        uint128 nodeId = minimum(tree, tree.root);
        key = tree.nodes[nodeId].key;
    }

    /**
     * @notice Get maximum key in tree
     */
    function getMax(Tree storage tree) internal view returns (uint256 key) {
        if(tree.root == NIL) revert EmptyTree();
        uint128 nodeId = maximum(tree, tree.root);
        key = tree.nodes[nodeId].key;
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

    function getSize(Tree storage tree, uint128 nodeId) private view returns (uint64) {
        return nodeId == NIL ? 0 : tree.nodes[nodeId].size;
    }

    function updateSize(Tree storage tree, uint128 nodeId) private {
        if (nodeId != NIL) {
            tree.nodes[nodeId].size = uint64(1 +
                uint256(getSize(tree, tree.nodes[nodeId].left)) +
                uint256(getSize(tree, tree.nodes[nodeId].right)));
        }
    }

    function minimum(Tree storage tree, uint128 nodeId) private view returns (uint128) {
        while (tree.nodes[nodeId].left != NIL) {
            nodeId = tree.nodes[nodeId].left;
        }
        return nodeId;
    }

    function maximum(Tree storage tree, uint128 nodeId) private view returns (uint128) {
        while (tree.nodes[nodeId].right != NIL) {
            nodeId = tree.nodes[nodeId].right;
        }
        return nodeId;
    }

    /*//////////////////////////////////////////////////////////////
                        RED-BLACK TREE MAINTENANCE
    //////////////////////////////////////////////////////////////*/

    function rotateLeft(Tree storage tree, uint128 nodeId) private {
        uint128 right = tree.nodes[nodeId].right;

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

    function rotateRight(Tree storage tree, uint128 nodeId) private {
        uint128 left = tree.nodes[nodeId].left;

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

    function insertFixup(Tree storage tree, uint128 nodeId) private {
        while (tree.nodes[tree.nodes[nodeId].parent].isRed) {
            uint128 parent = tree.nodes[nodeId].parent;
            uint128 grandparent = tree.nodes[parent].parent;

            if (parent == tree.nodes[grandparent].left) {
                uint128 uncle = tree.nodes[grandparent].right;

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
                uint128 uncle = tree.nodes[grandparent].left;

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

    function deleteFixup(Tree storage tree, uint128 nodeId) private {
        while (nodeId != tree.root && !tree.nodes[nodeId].isRed) {
            uint128 parent = tree.nodes[nodeId].parent;

            if (nodeId == tree.nodes[parent].left) {
                uint128 sibling = tree.nodes[parent].right;

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
                uint128 sibling = tree.nodes[parent].left;

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

    function transplant(Tree storage tree, uint128 target, uint128 replacement) private {
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
