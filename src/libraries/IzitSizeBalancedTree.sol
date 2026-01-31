pragma solidity ^0.8.0;

// ----------------------------------------------------------------------------
// Izit's Size Balanced Tree Library 
//
// A Solidity Size Balanced Tree binary search library to store and access a sorted
// list of unsigned integer data. The  algorithm rebalances the binary search tree,
// resulting in O(log n) insert, remove and search time (and ~gas)
//
// SPDX-License-Identifier: MIT
//
// Enjoy. (c) Izit 2025. The MIT Licence.
// ----------------------------------------------------------------------------

type Node_ptr is uint64; // 2^64 = 18, 446,744,073, 709,552,000

abstract contract IzitRBTree {

    Node_ptr internal constant NIL = Node_ptr.wrap(0);

    // pointer 0 for null point
    // left node smaller than parent
    // right node  larger than parent
    struct Node {
        uint256 key_ptr;
        Node_ptr parent;
        Node_ptr left;
        Node_ptr right;
        uint256 subTreeSize;
    }
    
    struct Tree {
        Node_ptr root;
        Node_ptr max_idx;
        mapping(Node_ptr => Node) nodes;
        mapping(uint256 => Node_ptr) keyMap;
    }

    function _less(uint256 ptr_a, uint256 ptr_b)
        internal
        virtual
    returns (bool);

    function _isNil(Node_ptr p) internal pure returns (bool) {
        return Node_ptr.unwrap(p) == Node_ptr.unwrap(NIL);
    }

    function query_min(Tree storage _tree, Node_ptr _sub_root)
        internal
        view
        returns (uint256 key_ptr)
    {
        Node_ptr x = _sub_root;
        if (_isNil(x)) return 0;

        while (!_isNil(_tree.nodes[x].left)) {
            x = _tree.nodes[x].left;
        }
        return _tree.nodes[x].key_ptr;

    }

    function query_max(Tree storage _tree, Node_ptr _sub_root)
        internal
        view
        returns (uint256 key_ptr)
    {
        Node_ptr x = _sub_root;
        if (_isNil(x)) return 0;

        while (!_isNil(_tree.nodes[x].right)) {
            x = _tree.nodes[x].right;
        }
        return _tree.nodes[x].key_ptr;

    }

    function min(Tree storage _tree) internal view returns (uint256) {
        return query_min(_tree, _tree.root);
    }

    function max(Tree storage _tree) internal view returns (uint256) {
        return query_max(_tree, _tree.root);
    }

    function contains(Tree storage _tree, uint256 key_ptr)
        internal
        view
        returns (bool)
    {
        return !_isNil(_tree.keyMap[key_ptr]);
    }


    function insert(uint256 key_ptr)
        public
    {

    
    }

    function remove(uint256 key_ptr)
        public
    {
    
    }

    function rotateLeft(Tree storage _tree, Node_ptr _node) private {
    
    }

    function rotateRight(Tree storage _tree, Node_ptr _node) private {

    }




}