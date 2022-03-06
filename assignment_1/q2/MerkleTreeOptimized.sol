// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";

/**
  Smart contract that adds an NFT to a Merkle Tree.
*/
contract MerkleTree {
    bytes32[] tree;
    uint256 constant leafLen = 2**32;
    uint256 filledLeaves;

    constructor() {
        // Fill the tree with zeroes for 2^32 leaves.
        // This results in a Merkle Array of length 1 + 2^1 + 2^2 + .... + 2^31
        // which equals 4294967295.
        for (uint256 i = 0; i < 4294967295; i++) {
            tree.push(bytes32(0));
        }
    }

    // Contract function that takes the details of an NFT and adds them to a Merkle Tree.
    function add(
        address sender,
        address receiver,
        uint256 tokenId,
        string calldata tokenURI
    ) public returns (bytes32) {
        bytes32 nftHash = hashNFT(sender, receiver, tokenId, tokenURI);
        updateTree(nftHash);
        return tree[tree.length - 1];
    }

    function hashNFT(
        address sender,
        address receiver,
        uint256 tokenId,
        string calldata tokenURI
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(sender, receiver, tokenId, tokenURI));
    }

    // Update the Merkle Tree with minimal number of hashing steps.
    // When a new leaf is added, only the tree nodes in the path from the leaf to the
    // root need to be updated with the hash of their child nodes.
    //
    // When a tree is stored in the form of an array, the parent of a node at index'i'
    // can be found at 'leafLen + i/2', where leafLen is the number of tree leaves.
    //
    // This process of updating a node's parent is carried on until we reach the root
    // node.
    function updateTree(bytes32 nftHash) private {
        tree[filledLeaves] = nftHash;
        uint256 idx = filledLeaves++;
        while (idx < tree.length - 1) {
            if (idx % 2 == 0) {
                tree[leafLen + idx / 2] = keccak256(
                    abi.encodePacked(tree[idx], tree[idx + 1])
                );
            } else {
                tree[leafLen + idx / 2] = keccak256(
                    abi.encodePacked(tree[idx - 1], tree[idx])
                );
            }
            idx = leafLen + idx / 2;
        }
    }
}
