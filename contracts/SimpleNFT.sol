// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

error CannotExceedMaxSupply();
error BelowMintPrice();

contract SimpleNFT is ERC721Enumerable, Ownable, ReentrancyGuard {
    // nft variables
    uint32 public immutable i_maxSupply;
    string private _baseTokenURI;
    uint256 private _mintPrice;

    // events
    event WithdrawFunds(uint256 indexed amount);
    event Mint(address indexed minter, uint256 indexed tokenId);

    constructor(
        string memory name,
        string memory symbol,
        string memory baseTokenURI,
        uint256 initialMintPrice,
        uint32 maxSupply
    ) ERC721(name, symbol) {
        _baseTokenURI = baseTokenURI;
        _mintPrice = initialMintPrice;
        i_maxSupply = maxSupply;
    }

    // managing token uri
    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        return
            string(abi.encodePacked(_baseTokenURI, Strings.toString(tokenId)));
    }

    // managing mint price
    function setMintPrice(uint256 newMintPrice) external onlyOwner {
        _mintPrice = newMintPrice;
    }

    function mintPrice() public view returns (uint256) {
        return _mintPrice;
    }

    // withdraw funds in contract
    function withdrawEth() external payable onlyOwner {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
        emit WithdrawFunds(address(this).balance);
    }

    // public mint
    function publicMint() external payable nonReentrant returns (uint256) {
        uint256 newTokenId = totalSupply();
        if (newTokenId > i_maxSupply) revert CannotExceedMaxSupply();
        if (msg.value < _mintPrice) revert BelowMintPrice();
        _safeMint(msg.sender, newTokenId);
        emit Mint(msg.sender, newTokenId);
        return newTokenId;
    }
}
