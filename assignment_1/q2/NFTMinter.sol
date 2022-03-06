// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "./MerkleTree.sol";

contract NFTMinter is ERC721URIStorage {
    using Strings for uint256;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    MerkleTree private merkleTree;

    constructor() ERC721("NFTMinter", "NFTMint") {
        merkleTree = new MerkleTree();
    }

    function tokenURI(uint256 tokenId)
        public
        pure
        override
        returns (string memory)
    {
        bytes memory dataURI = abi.encodePacked(
            "{",
            '"name": "ZKU One Ape #',
            tokenId.toString(),
            '"',
            '"description": "Token minted for ZKU One with token id: #',
            tokenId.toString(),
            '"',
            "}"
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(dataURI)
                )
            );
    }

    /**
     * Use OpenZeppelin smart contract lib to mint an ERC721 token.
     * Once minted, the token is added to a merkle tree by calling the MerkleTree smart contract.
     *
     * to is the address of the new token's owner.
     * tokenUri is the URI associated with the token, stored on-chain.
     */
    function mintToken(address to, string memory tokenUri)
        public
        returns (uint256)
    {
        _tokenIds.increment();

        uint256 tokenId = _tokenIds.current();
        _mint(to, tokenId);
        _setTokenURI(tokenId, tokenUri);

        merkleTree.add(msg.sender, to, tokenId, tokenUri);

        return tokenId;
    }
}
