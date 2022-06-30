// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

error DepositFailed();
error NoDeposit();
error WithdrawFailed();
error TokenNotFound();

contract NFTLending is ReentrancyGuard, Ownable {
    // user address -> erc721 address -> deposit amount
    mapping(address => mapping(address => uint256[]))
        public s_accountsToNFTDeposits;

    // events
    event Deposit(address indexed account, uint256 indexed tokenId);
    event Withdraw(address indexed account, uint256 indexed tokenId);

    constructor() {}

    function depositNFT(address nft, uint256 tokenId) external nonReentrant {
        s_accountsToNFTDeposits[msg.sender][nft].push(tokenId);
        ERC721(nft).transferFrom(msg.sender, address(this), tokenId);
        emit Deposit(msg.sender, tokenId);
        address newOwner = ERC721(nft).ownerOf(tokenId);
        if (newOwner != address(this)) revert DepositFailed();
    }

    function withdrawNFT(address nft, uint256 tokenId) external nonReentrant {
        if (s_accountsToNFTDeposits[msg.sender][nft].length < 1)
            revert NoDeposit();
        bool deleted = false;
        for (
            uint256 index = 0;
            index < s_accountsToNFTDeposits[msg.sender][nft].length;
            index++
        ) {
            if (s_accountsToNFTDeposits[msg.sender][nft][index] == tokenId) {
                delete s_accountsToNFTDeposits[msg.sender][nft][index];
                deleted = true;
            }
        }
        if (!deleted) revert TokenNotFound();
        ERC721(nft).transferFrom(address(this), msg.sender, tokenId);
        emit Withdraw(msg.sender, tokenId);
        address newOwner = ERC721(nft).ownerOf(tokenId);
        if (newOwner != msg.sender) revert WithdrawFailed();
    }
}
