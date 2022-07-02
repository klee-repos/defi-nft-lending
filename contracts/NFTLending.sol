// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import "./PriceConversion.sol";

error DepositFailed(address nft, uint256 tokenId);
error NoDeposit(address account, address nft);
error WithdrawFailed(address nft, uint256 tokenId);
error TokenNotFound(uint256 tokenId);
error MustBeGreaterThanZero(uint256 amount);
error InsufficientFunds(address account, uint256 amount);
error NegativeTreasury(address account, uint256 amount);
error NFTNowAllowed(address nft);

contract NFTLending is ReentrancyGuard, Ownable {
    // eth to usd functions
    using PriceConversion for uint256;

    // user address -> erc721 address -> deposit amount
    mapping(address => mapping(address => uint256[]))
        public s_accountsToNFTDeposits;
    // allowed projects
    address[] public s_allowedNFTs;

    // user address -> eth deposit
    mapping(address => uint256) public s_accountsToEthDeposit;

    // nft address -> floor eth value
    mapping(address => uint256) public s_nftFloorEthValue;

    // treasury
    uint256 public s_treasuryEth;

    // borrowing
    uint256 public s_borrowPower = 30;
    // user address -> eth borrow amount

    // events
    event Deposit(address indexed account, uint256 indexed tokenId);
    event Withdraw(address indexed account, uint256 indexed tokenId);
    event EthDeposited(address indexed account, uint indexed amount);
    event WithdrawEth(address indexed account, uint256 indexed amount);
    event ProjectApproved(address indexed account);
    event NewFloor(address indexed nft, uint256 indexed amount);

    // price feed
    AggregatorV3Interface public priceFeed;

    constructor(address priceFeedAddress) {
        priceFeed = AggregatorV3Interface(priceFeedAddress);
    }

    function approveNFT(address nft) external onlyOwner {
        s_allowedNFTs.push(nft);
        emit ProjectApproved(nft);
    }

    function setNFTFloorEthValue(address nft, uint256 amount)
        external
        onlyOwner
        moreThanZero(amount)
    {
        s_nftFloorEthValue[nft] = amount;
        emit NewFloor(nft, amount);
    }

    function getNFTFloorEthValue(address nft) public view returns (uint256) {
        return s_nftFloorEthValue[nft];
    }

    function getNFTFloorUSDValue(address nft) public view returns (uint256) {
        uint256 usdFloorValue = s_nftFloorEthValue[nft].convertToUSD(priceFeed);
        return usdFloorValue;
    }

    function ethToUSD(uint256 amount) public view returns (uint256) {
        return amount.convertToUSD(priceFeed);
    }

    function accountCollateral(address user) public view returns (uint256) {
        uint256 totalCollateral = 0;
        for (
            uint256 projectIndex = 0;
            projectIndex < s_allowedNFTs.length;
            projectIndex++
        ) {
            for (
                uint256 tokenIndex = 0;
                tokenIndex <
                s_accountsToNFTDeposits[user][s_allowedNFTs[projectIndex]]
                    .length;
                tokenIndex++
            ) {
                uint256 usdFloorValue = getNFTFloorUSDValue(
                    s_allowedNFTs[projectIndex]
                );
                totalCollateral += usdFloorValue;
            }
        }
        return totalCollateral;
    }

    function depositNFT(address nft, uint256 tokenId)
        external
        isAllowedNFT(nft)
        nonReentrant
    {
        s_accountsToNFTDeposits[msg.sender][nft].push(tokenId);
        ERC721(nft).transferFrom(msg.sender, address(this), tokenId);
        emit Deposit(msg.sender, tokenId);

        address newOwner = ERC721(nft).ownerOf(tokenId);
        if (newOwner != address(this)) revert DepositFailed(nft, tokenId);
    }

    function healthScore(address account) public view returns (uint256) {}

    function borrowEth(uint256 amount)
        external
        payable
        nonReentrant
        moreThanZero(amount)
    {}

    function withdrawNFT(address nft, uint256 tokenId)
        external
        isAllowedNFT(nft)
        nonReentrant
    {
        if (s_accountsToNFTDeposits[msg.sender][nft].length < 1)
            revert NoDeposit(msg.sender, nft);
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
        if (!deleted) revert TokenNotFound(tokenId);
        ERC721(nft).transferFrom(address(this), msg.sender, tokenId);
        emit Withdraw(msg.sender, tokenId);
        address newOwner = ERC721(nft).ownerOf(tokenId);
        if (newOwner != msg.sender) revert WithdrawFailed(nft, tokenId);
    }

    function depositEth()
        external
        payable
        moreThanZero(msg.value)
        nonReentrant
    {
        s_accountsToEthDeposit[msg.sender] += msg.value;
        s_treasuryEth += msg.value;
        emit EthDeposited(msg.sender, msg.value);
    }

    function withdrawEth(uint256 amount)
        external
        payable
        moreThanZero(amount)
        nonReentrant
    {
        if (amount > s_accountsToEthDeposit[msg.sender])
            revert InsufficientFunds(msg.sender, amount);
        if (amount > s_treasuryEth) revert NegativeTreasury(msg.sender, amount);
        s_accountsToEthDeposit[msg.sender] -= amount;
        s_treasuryEth -= amount;
        payable(msg.sender).transfer(amount);
        emit WithdrawEth(msg.sender, msg.value);
    }

    // modifiers

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) revert MustBeGreaterThanZero(amount);
        _;
    }

    modifier isAllowedNFT(address nft) {
        if (s_nftFloorEthValue[nft] == 0) revert NFTNowAllowed(nft);
        _;
    }
}
