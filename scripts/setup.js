const { ethers } = require("hardhat");
require("dotenv").config;

const ERC721_NAME = "KVN NFTs";
const ERC721_SYMBOL = "KVN";
const ERC721_BASE_URI = "https://www.ipfs.com/";
const ERC721_MINT_PRICE = ethers.utils.parseEther("0.01");
const ERC721_MAX_SUPPLY = 2;

const PRICE_FEED_DECIMALS = 8;
const PRICE_FEED_INITIAL_PRICE = "100000000000";

const NFT_PROJECT_ETH_FLOOR = ethers.utils.parseEther(".45");
const DEPOSIT_AMOUNT_ETH = ethers.utils.parseEther("0.3");

async function deploySimpleNFT() {
  let SimpleNFTFactory = await ethers.getContractFactory("SimpleNFT");
  let SimpleNFT = await SimpleNFTFactory.deploy(
    ERC721_NAME,
    ERC721_SYMBOL,
    ERC721_BASE_URI,
    ERC721_MINT_PRICE,
    ERC721_MAX_SUPPLY
  );
  console.log(`SimpleNFT address: ${SimpleNFT.address}`);
  return SimpleNFT;
}

async function mintSomeNFTs(SimpleNFT) {
  let txMint;
  for (let i = 0; i <= ERC721_MAX_SUPPLY; i++) {
    txMint = await SimpleNFT.publicMint({ value: ERC721_MINT_PRICE });
    let txReceipt = await txMint.wait();
    console.log(txReceipt);
  }
  return;
}

async function deployAggregatorV3InterfaceMock() {
  let AggregatorV3InterfaceFactory = await ethers.getContractFactory(
    "MockV3Aggregator"
  );
  let AggregatorV3Interface = await AggregatorV3InterfaceFactory.deploy(
    PRICE_FEED_DECIMALS,
    PRICE_FEED_INITIAL_PRICE
  );
  console.log(
    `AggregatorV3Interface address: ${AggregatorV3Interface.address}`
  );
  return AggregatorV3Interface;
}

async function deployNFTLending(AggregatorV3Interface) {
  let NFTLendingFactory = await ethers.getContractFactory("NFTLending");
  let NFTLending = await NFTLendingFactory.deploy(
    AggregatorV3Interface.address
  );
  console.log(`NFTLending address: ${NFTLending.address}`);
  return NFTLending;
}

async function addNftToAllowlist(NFTLending, SimpleNFT) {
  let tx = await NFTLending.approveNFT(SimpleNFT.address);
  let txReceipt = await tx.wait();
  console.log(txReceipt);
  return;
}

async function setNftFloor(NFTLending, SimpleNFT) {
  let tx = await NFTLending.setNFTFloorEthValue(
    SimpleNFT.address,
    NFT_PROJECT_ETH_FLOOR
  );
  let txReceipt = await tx.wait();
  console.log(txReceipt);
  return;
}

async function depositETH(NFTLending) {
  let tx = await NFTLending.depositETH({
    value: DEPOSIT_AMOUNT_ETH,
  });
  await tx.wait();
  return;
}

const main = async () => {
  // deploy lending
  let SimpleNFT = await deploySimpleNFT();
  // mint nft
  await mintSomeNFTs(SimpleNFT);
  // deploy aggregatorV3Mock price feed
  let AggregatorV3Interface = await deployAggregatorV3InterfaceMock();
  // deploy nft lending
  let NFTLending = await deployNFTLending(AggregatorV3Interface);
  // add nft to allow list
  await addNftToAllowlist(NFTLending, SimpleNFT);
  // set floor value in eth for nft
  await setNftFloor(NFTLending, SimpleNFT);
  // deposit eth
  await depositETH(NFTLending);
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.log(error);
    process.exit(1);
  });
