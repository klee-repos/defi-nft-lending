const { ethers } = require("hardhat");
const { assert, expect } = require("chai");
require("dotenv").config;

const { WALLET_ADDRESS } = process.env;

const ERC721_NAME = "KVN NFTs";
const ERC721_SYMBOL = "KVN";
const ERC721_BASE_URI = "https://www.ipfs.com/";
const ERC721_MINT_PRICE = ethers.utils.parseEther("0.01");
const ERC721_MAX_SUPPLY = 2;

const PRICE_FEED_DECIMALS = 8;
const PRICE_FEED_INITIAL_PRICE = "100000000000";

const NFT_PROJECT_ETH_FLOOR = ethers.utils.parseEther(".45");

const BORROW_POWER = 30;
const BORROW_INTEREST_RATE = 10;
const BORROW_AMOUNT_ETH = ethers.utils.parseEther(".15");
const DEPOSIT_AMOUNT_ETH = ethers.utils.parseEther("0.3");
const PAY_BACK_ETH = ethers.utils.parseEther("0.1");
const LOAN_DURATION = 30;

function log(v) {
  console.log(v);
}

describe("DeFi NFTLending unit tests", function () {
  // SimpleNFT tests
  let SimpleNFTFactory, SimpleNFT;

  describe("deploy SimpleNFT", function () {
    it("deploy contract", async () => {
      SimpleNFTFactory = await ethers.getContractFactory("SimpleNFT");
      SimpleNFT = await SimpleNFTFactory.deploy(
        ERC721_NAME,
        ERC721_SYMBOL,
        ERC721_BASE_URI,
        ERC721_MINT_PRICE,
        ERC721_MAX_SUPPLY
      );
      assert(SimpleNFT.address, "No contract address found");
    });

    it("check name", async () => {
      let name = await SimpleNFT.name();
      assert(name === ERC721_NAME, "unexpected name on deployed contract");
    });

    it("check max supply", async () => {
      let maxSupply = await SimpleNFT.i_maxSupply();
      assert(maxSupply === ERC721_MAX_SUPPLY, "wrong max supply");
    });

    it("check mint price", async () => {
      let mintPrice = await SimpleNFT.mintPrice();
      assert(
        mintPrice.toString() === ERC721_MINT_PRICE.toString(),
        "wrong mint price"
      );
    });
  });

  describe("minting nfts", function () {
    it("mint some nfts", async () => {
      let txMint;
      for (let i = 0; i <= ERC721_MAX_SUPPLY; i++) {
        txMint = await SimpleNFT.publicMint({ value: ERC721_MINT_PRICE });
        let txReceipt = await txMint.wait();
        assert(txReceipt.events[0].event === "Transfer", "NFT mint failed");
      }
    });

    it("test withdraw", async () => {
      let tx = await SimpleNFT.withdrawEth();
      let txReceipt = await tx.wait();
      assert(
        txReceipt.events[0].event === "WithdrawFunds",
        "balance should be 0 after withdrawal"
      );
    });
  });

  // AggregatorV3Interface tests
  let AggregatorV3InterfaceFactory, AggregatorV3Interface;
  describe("deploy AggregatorV3InterfaceMock", function () {
    it("deploy contract", async () => {
      AggregatorV3InterfaceFactory = await ethers.getContractFactory(
        "MockV3Aggregator"
      );
      AggregatorV3Interface = await AggregatorV3InterfaceFactory.deploy(
        PRICE_FEED_DECIMALS,
        PRICE_FEED_INITIAL_PRICE
      );
      assert(AggregatorV3Interface.address, "missing contract address");
    });
  });

  //NFTLending tests
  let NFTLendingFactory, NFTLending, AccountCollateral, TreasuryBalance;
  let ApprovedTokenIds = [];

  describe("deploy NFTLending", function () {
    it("deploy contract", async () => {
      NFTLendingFactory = await ethers.getContractFactory("NFTLending");
      NFTLending = await NFTLendingFactory.deploy(
        AggregatorV3Interface.address
      );
      assert(NFTLending.address, "No contract address found");
    });
  });

  describe("allow nft project", function () {
    it("approve project", async () => {
      let tx = await NFTLending.approveNFT(SimpleNFT.address);
      let txReceipt = await tx.wait();
      assert(txReceipt.events[0].event === "ProjectApproved");
    });
  });

  describe("set nft floor", function () {
    it("set nft floor eth value", async () => {
      let tx = await NFTLending.setNFTFloorEthValue(
        SimpleNFT.address,
        NFT_PROJECT_ETH_FLOOR
      );
      let txReceipt = await tx.wait();
      assert(
        txReceipt.events[0].event === "NewFloor",
        "setting new floor failed"
      );
    });

    it("check nft floor usd value", async () => {
      let nftFloorUSD = await NFTLending.getNFTFloorUSDValue(SimpleNFT.address);
      let expectedFloorUSD = await NFTLending.ethToUSD(NFT_PROJECT_ETH_FLOOR);
      assert(
        nftFloorUSD.toString() === expectedFloorUSD.toString(),
        "unexpected floor eth value"
      );
    });
  });

  describe("transfer some nfts to NFTLending", function () {
    it("approve transfers", async () => {
      for (let i = 0; i < ERC721_MAX_SUPPLY; i++) {
        ApprovedTokenIds.push(
          await SimpleNFT.tokenOfOwnerByIndex(WALLET_ADDRESS, i)
        );
      }
      for (let a in ApprovedTokenIds) {
        let tx = await SimpleNFT.approve(
          NFTLending.address,
          ApprovedTokenIds[a]
        );
        let txReceipt = await tx.wait();
        assert(
          txReceipt.events[0].event === "Approval",
          "approval of nft failed"
        );
      }
    });

    it("send nft to NFTLending", async () => {
      for (let a in ApprovedTokenIds) {
        let tx = await NFTLending.depositNFT(
          SimpleNFT.address,
          ApprovedTokenIds[a]
        );
        let txReceipt = await tx.wait();
        assert(txReceipt.events[2].event === "Deposit", "nft deposit failed");
      }
    });

    it("confirm new owner", async () => {
      for (let a in ApprovedTokenIds) {
        let tx = await SimpleNFT.ownerOf(ApprovedTokenIds[a]);
        assert(tx === NFTLending.address, "wrong owner");
      }
    });
  });

  describe("account info", function () {
    it("check collateral value", async () => {
      let usdFloor = await NFTLending.getNFTFloorUSDValue(SimpleNFT.address);
      let totalValue =
        usdFloor * ethers.BigNumber.from(ERC721_MAX_SUPPLY.toString());
      AccountCollateral = await NFTLending.accountCollateral(WALLET_ADDRESS);
      assert(
        totalValue.toString() === AccountCollateral.toString(),
        "unexpected collateral value"
      );
    });

    it("check max borrow amount", async () => {
      let borrowMax = await NFTLending.borrowMaxUSD(WALLET_ADDRESS);
      let expected = (AccountCollateral * BORROW_POWER) / 100;
      assert(
        borrowMax.toString() === expected.toString(),
        "unexpected max borrow amount"
      );
    });
  });

  describe("deposit some eth into treasury", function () {
    it("deposit eth", async () => {
      let tx = await NFTLending.depositETH({
        value: DEPOSIT_AMOUNT_ETH,
      });
      await tx.wait();
      TreasuryBalance = await NFTLending.s_treasuryEth();
      assert(
        TreasuryBalance.toString() === DEPOSIT_AMOUNT_ETH.toString(),
        "deposit amount incorrect"
      );
    });
  });

  describe("borrow some eth", function () {
    it("borrow", async () => {
      let tx = await NFTLending.borrowEth(BORROW_AMOUNT_ETH, LOAN_DURATION);
      let txReceipt = await tx.wait();
      assert(txReceipt.events[0].event === "BorrowEth", "borrowing eth failed");
      let interest = (BORROW_AMOUNT_ETH * BORROW_INTEREST_RATE) / 100;
      TreasuryBalance = await NFTLending.s_treasuryEth();
      let expectedTreasury = BORROW_AMOUNT_ETH - interest;
      assert(
        expectedTreasury.toString() === TreasuryBalance.toString(),
        "treasury balance incorrect"
      );
    });

    it("check health score", async () => {
      let healthScore = await NFTLending.healthScore(WALLET_ADDRESS);
      let maxBorrowUSD = await NFTLending.borrowMaxUSD(WALLET_ADDRESS);
      let borrowedETH = await NFTLending.s_accountsToEthBorrow(WALLET_ADDRESS);
      let borrowedUSD = await NFTLending.ethToUSD(borrowedETH);
      let expectedScore = parseInt((maxBorrowUSD * 100) / borrowedUSD);
      assert(
        healthScore.toString() === expectedScore.toString(),
        "unexpected health score"
      );
    });

    it("pay back some of loan", async () => {
      let totalLoans = await NFTLending.s_accountsToTotalLoans(WALLET_ADDRESS);
      let loanIds = [];
      for (let l = 0; l < totalLoans; l++) {
        loanIds.push(await NFTLending.s_accountsToLoanIds(WALLET_ADDRESS, l));
      }
      let tx = await NFTLending.payBackETH(loanIds[0], { value: PAY_BACK_ETH });
      let txReceipt = await tx.wait();
      assert(
        txReceipt.events[0].event === "LoanRepayment",
        "loan repayment failed"
      );
    });
  });

  describe("try to withdraw nft", function () {
    it("withdraw nft from NFTLending", async () => {
      let tx = await NFTLending.withdrawNFT(
        SimpleNFT.address,
        ApprovedTokenIds[0]
      );
      let txReceipt = await tx.wait();
    });
  });
});
