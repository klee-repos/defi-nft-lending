const { ethers } = require("hardhat");
const { assert } = require("chai");
require("dotenv").config;

const { WALLET_ADDRESS } = process.env;

const ERC721_NAME = "KVN NFTs";
const ERC721_SYMBOL = "KVN";
const ERC721_BASE_URI = "https://www.ipfs.com/";
const ERC721_MINT_PRICE = ethers.utils.parseEther("0.01");
const ERC721_MAX_SUPPLY = 5;

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

  //NFTLending tests
  let NFTLendingFactory, NFTLending, ApprovedTokenId;

  describe("deploy NFTLending", function () {
    it("deploy contract", async () => {
      NFTLendingFactory = await ethers.getContractFactory("NFTLending");
      NFTLending = await NFTLendingFactory.deploy();
      assert(NFTLending.address, "No contract address found");
    });
  });

  describe("transfer nft to NFTLending", function () {
    it("approve transfer", async () => {
      ApprovedTokenId = await SimpleNFT.tokenOfOwnerByIndex(WALLET_ADDRESS, 0);
      let tx = await SimpleNFT.approve(NFTLending.address, ApprovedTokenId);
      let txReceipt = await tx.wait();
      assert(
        txReceipt.events[0].event === "Approval",
        "approval of nft failed"
      );
    });

    it("send nft to NFTLending", async () => {
      let tx = await NFTLending.depositNFT(SimpleNFT.address, ApprovedTokenId);
      let txReceipt = await tx.wait();
      assert(txReceipt.events[2].event === "Deposit", "nft deposit failed");
    });

    it("confirm new owner", async () => {
      let tx = await SimpleNFT.ownerOf(ApprovedTokenId);
      assert(tx === NFTLending.address, "wrong owner");
    });
  });

  describe("withdraw nft from NFTLending", function () {
    it("withdraw nft from NFTLending", async () => {
      let tx = await NFTLending.withdrawNFT(SimpleNFT.address, ApprovedTokenId);
      let txReceipt = await tx.wait();
      assert(txReceipt.events[2].event === "Withdraw", "nft withdraw failed");
    });

    it("confirm new owner", async () => {
      let tx = await SimpleNFT.ownerOf(ApprovedTokenId);
      assert(tx === WALLET_ADDRESS, "wrong owner");
    });
  });
});
