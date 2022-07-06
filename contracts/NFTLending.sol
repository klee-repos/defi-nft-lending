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
error InsufficientCollateral(address account);
error AmountMoreThanBorrowed(uint256 loan, uint256 amount);

contract NFTLending is ReentrancyGuard, Ownable {
    // eth to usd functions
    using PriceConversion for uint256;

    // user address -> erc721 address -> array of token ids
    mapping(address => mapping(address => uint256[]))
        public s_accountsToNFTDeposits;
    mapping(address => mapping(address => uint256))
        public s_accountsToTotalNFTDeposits;

    // allowed projects
    address[] public s_allowedNFTs;
    uint256 public s_totalAllowedNFTs;

    // user address -> eth deposit
    mapping(address => uint256) public s_accountsToEthDeposit;

    // user address -> eth borrow
    mapping(address => uint256) public s_accountsToEthBorrow;

    // user address -> total loans
    mapping(address => uint256) public s_accountsToTotalLoans;

    // loan id
    uint256 public s_loanId = 0;

    // user address -> loan ids
    mapping(address => uint256[]) public s_accountsToLoanIds;

    // user address -> loan id -> deadline
    mapping(address => mapping(uint256 => uint256))
        public s_accountsToLoanIdToLoanDeadline;

    // user address -> loan id -> eth borrow
    mapping(address => mapping(uint256 => uint256))
        public s_accountsToLoanIdToEthBorrow;

    // borrowing
    uint256 public s_borrowInterestRate = 10;
    uint256 public s_borrowPower = 30;
    uint8 public immutable i_LIQUIDATION_THRESHOLD = 100;

    // represent delete
    uint256 private immutable i_ARRAY_DELETE_ID = 5373135;

    // nft address -> floor eth value
    mapping(address => uint256) public s_nftFloorEthValue;

    // treasury
    uint256 public s_treasuryEth;

    // events
    event Deposit(address indexed account, uint256 indexed tokenId);
    event Withdraw(address indexed account, uint256 indexed tokenId);
    event EthDeposited(address indexed account, uint indexed amount);
    event WithdrawEth(address indexed account, uint256 indexed amount);
    event ProjectApproved(address indexed account);
    event NewFloor(address indexed nft, uint256 indexed amount);
    event BorrowEth(address indexed account, uint256 indexed amount);
    event HealthScore(address indexed account, uint256 indexed userScore);
    event DeleteDeposit(uint256 indexed tokenId);
    event LoanRepayment(address indexed account, uint256 indexed amount);

    // price feed
    AggregatorV3Interface public priceFeed;

    constructor(address priceFeedAddress) {
        priceFeed = AggregatorV3Interface(priceFeedAddress);
    }

    function approveNFT(address nft) external onlyOwner {
        s_allowedNFTs.push(nft);
        s_totalAllowedNFTs++;
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

    function ethToUSD(uint256 amount)
        public
        view
        moreThanZero(amount)
        returns (uint256)
    {
        return amount.convertToUSD(priceFeed);
    }

    function accountBorrowed(address user) public view returns (uint256) {
        return s_accountsToEthBorrow[user];
    }

    function depositNFT(address nft, uint256 tokenId)
        external
        isAllowedNFT(nft)
        nonReentrant
    {
        s_accountsToNFTDeposits[msg.sender][nft].push(tokenId);
        s_accountsToTotalNFTDeposits[msg.sender][nft]++;
        ERC721(nft).transferFrom(msg.sender, address(this), tokenId);
        emit Deposit(msg.sender, tokenId);

        address newOwner = ERC721(nft).ownerOf(tokenId);
        if (newOwner != address(this)) revert DepositFailed(nft, tokenId);
    }

    function borrowMaxUSD(address user) public view returns (uint256) {
        uint256 userCollateral = accountCollateral(user);
        uint256 maxUSD;
        if (userCollateral == 0) {
            maxUSD = 0;
        } else {
            maxUSD = (userCollateral * s_borrowPower) / 100;
        }
        return maxUSD;
    }

    function healthScore(address account) public view returns (uint256) {
        uint256 maxBorrow = borrowMaxUSD(account);
        uint256 currentBorrowed = s_accountsToEthBorrow[account].convertToUSD(
            priceFeed
        );
        uint256 score;
        if (currentBorrowed > 0) {
            score = (maxBorrow * 100) / currentBorrowed;
        } else {
            score = i_LIQUIDATION_THRESHOLD;
        }
        return score;
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

    function borrowEth(uint256 amount, uint256 duration)
        external
        payable
        nonReentrant
        moreThanZero(amount)
        moreThanZero(duration)
    {
        uint256 interest = (amount * s_borrowInterestRate) / 100;
        uint256 amountWithInterest = amount + interest;
        if (amountWithInterest > s_treasuryEth)
            revert NegativeTreasury(msg.sender, amountWithInterest);
        // add amount to total borrowed
        s_accountsToEthBorrow[msg.sender] += amountWithInterest;
        // add amount to a loan id
        s_accountsToLoanIdToEthBorrow[msg.sender][
            s_loanId
        ] = amountWithInterest;
        // add deadline to the loan id
        s_accountsToLoanIdToLoanDeadline[msg.sender][
            s_loanId
        ] = calculateLoanDeadline(duration);
        // associate loan id to the user
        s_accountsToLoanIds[msg.sender].push(s_loanId);
        s_accountsToTotalLoans[msg.sender]++;
        s_loanId++;
        // ensure health score is green after loan
        uint256 userScore = healthScore(msg.sender);
        if (userScore < i_LIQUIDATION_THRESHOLD)
            revert InsufficientCollateral(msg.sender);
        // deduct loan amount from treasury
        s_treasuryEth -= amountWithInterest;
        // send eth loan to user
        payable(msg.sender).transfer(amountWithInterest);
        emit BorrowEth(msg.sender, amountWithInterest);
    }

    function calculateLoanDeadline(uint256 duration)
        public
        view
        moreThanZero(duration)
        returns (uint256 deadline)
    {
        deadline = block.timestamp + (duration * 1 seconds);
    }

    function withdrawNFT(address nft, uint256 tokenId)
        external
        isAllowedNFT(nft)
        nonReentrant
    {
        // remove tokenId from deposits
        if (s_accountsToNFTDeposits[msg.sender][nft].length < 1)
            revert NoDeposit(msg.sender, nft);
        bool deleted = false;
        uint256 newLength = s_accountsToNFTDeposits[msg.sender][nft].length - 1;
        uint256[] memory newTokenIds = new uint256[](newLength);
        uint256 newIndex = 0;
        for (
            uint256 index = 0;
            index < s_accountsToNFTDeposits[msg.sender][nft].length;
            index++
        ) {
            if (s_accountsToNFTDeposits[msg.sender][nft][index] != tokenId) {
                newTokenIds[newIndex] = s_accountsToNFTDeposits[msg.sender][
                    nft
                ][index];
                newIndex++;
            } else {
                emit DeleteDeposit(
                    s_accountsToNFTDeposits[msg.sender][nft][index]
                );
                deleted = true;
            }
        }
        s_accountsToNFTDeposits[msg.sender][nft] = newTokenIds;
        s_accountsToTotalNFTDeposits[msg.sender][nft]--;
        if (!deleted) revert TokenNotFound(tokenId);

        // check health score if withdrawn
        uint256 userScore = healthScore(msg.sender);
        emit HealthScore(msg.sender, userScore);
        if (userScore < i_LIQUIDATION_THRESHOLD)
            revert InsufficientCollateral(msg.sender);
        // transfer nft
        ERC721(nft).transferFrom(address(this), msg.sender, tokenId);
        emit Withdraw(msg.sender, tokenId);
        address newOwner = ERC721(nft).ownerOf(tokenId);
        if (newOwner != msg.sender) revert WithdrawFailed(nft, tokenId);
    }

    function payBackETH(uint256 loanId)
        external
        payable
        moreThanZero(msg.value)
        nonReentrant
    {
        if (msg.value > s_accountsToLoanIdToEthBorrow[msg.sender][loanId])
            revert AmountMoreThanBorrowed(
                s_accountsToLoanIdToEthBorrow[msg.sender][loanId],
                msg.value
            );
        s_accountsToLoanIdToEthBorrow[msg.sender][loanId] -= msg.value;
        s_accountsToEthBorrow[msg.sender] -= msg.value;
        s_treasuryEth += msg.value;
        emit LoanRepayment(msg.sender, msg.value);
    }

    function depositETH()
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
