pragma solidity ^0.8.0;

// ----------------------------------------------------------------------------
// Izit's Red-Black Tree Library 
//
// A Solidity Red-Black Tree binary search library to store and access a sorted
// list of unsigned integer data. The Red-Black algorithm rebalances the binary
// search tree, resulting in O(log n) insert, remove and search time (and ~gas)
//
// SPDX-License-Identifier: MIT
//
// Enjoy. (c) Izit 2025. The MIT Licence.
// ----------------------------------------------------------------------------

type Node_ptr is uint64; // 2^64 = 18, 446,744,073, 709,552,000

abstract contract IzitRBTree {

    Node_ptr internal constant NIL = Node_ptr.wrap(0);

    // pointer 0 for null point
    // left node is smaller than parent
    // right node is larger than parent
    struct Node {
        uint256 key_ptr;
        Node_ptr parent;
        Node_ptr left;
        Node_ptr right;
        bool isRed;
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
        return p == NIL;
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

    function contains(Tree storage _tree, uint256 _key_p)
        internal
        view
        returns (bool)
    {
        return !_isNil(_tree.keyMap[_key_p]);
    }

    function next_idx(Node_ptr p1) internal view returns (Node_ptr p2) {
        unchecked {
            uint64 raw = Node_ptr.unwrap(p1) % 2**64 + 1;
            p2 = Node_ptr.wrap(raw);
            _tree.max_idx = p2;
        }
    }

    function insert(Tree storage _tree, uint256 _key_p) {
        Node_ptr ptr1 = _tree.root;
        Node_ptr prev= NIL;

        while( ptr1 != NIL ) {
            if( _less( _key_p, _tree.nodes[ptr1].key_ptr) ) {
                prev = ptr1;
                ptr1 = _tree.nodes[ptr1].left;
            } else {
                prev = ptr1;
                ptr1 = _tree.nodes[ptr1].right;
            }
        }

        while(_tree.nodes[_tree.max_idx] != NIL) {
            _tree.max_idx = next_idx(_tree.max_idx);
        }

        _tree.keyMap[_key_p] = _tree.max_idx;
        _tree.nodes[_tree.max_idx] = Node(
            key_ptr: _key_p,
            parent : prev,
            left : Node_ptr.wrap(0),
            right : Node_ptr.wrap(0),
            isRed: true
        );

        if (prev == NIL) {
            _tree.root = _tree.max_idx;
        } else if( _less( _key_p, _tree.nodes[prev].key_ptr) ) {
            _tree.nodes[prev].left = _tree.max_idx;
        } else {
            _tree.nodes[prev].right = _tree.max_idx;
        }

    
    }

    function remove(Tree _tree, uint256 key_ptr) {
    
    }

    function rotateLeft(Tree _tree, Node_ptr _node) private {
    
        Node_ptr y = _tree.nodes[x].right;
        require(!_isNil(y), "RBTree: Rotate nil right");

        // x.right = y.left
        _tree.nodes[x].right = _tree.nodes[y].left;
        if (!_isNil(_tree.nodes[y].left)) {
            _tree.nodes[_tree.nodes[y].left].parent = x;
        }

        // y.parent = x.parent
        Node_ptr xParent = _tree.nodes[x].parent;
        _tree.nodes[y].parent = xParent;

        if (_isNil(xParent)) {
            _tree.root = y; 
        } else if (x == _tree.nodes[xParent].left) {
            _tree.nodes[xParent].left = y;
        } else {
            _tree.nodes[xParent].right = y;
        }

        // y.left = x
        _tree.nodes[y].left = x;
        _tree.nodes[x].parent = y;
    }

    function rotateRight(Tree _tree, Node_ptr _node) private {

        Node_ptr y = _tree.nodes[x].left;
        require(!_isNil(y), "RBTree: Rotate nil left");

        // x.left = y.right
        _tree.nodes[x].left = _tree.nodes[y].right;
        if (!_isNil(_tree.nodes[y].right)) {
            _tree.nodes[_tree.nodes[y].right].parent = x;
        }

        // y.parent = x.parent
        Node_ptr xParent = _tree.nodes[x].parent;
        _tree.nodes[y].parent = xParent;

        if (_isNil(xParent)) {
            _tree.root = y;
        } else if (x == _tree.nodes[xParent].right) {
            _tree.nodes[xParent].right = y;
        } else {
            _tree.nodes[xParent].left = y;
        }

        // y.right = x
        _tree.nodes[y].right = x;
        _tree.nodes[x].parent = y;

    }




}