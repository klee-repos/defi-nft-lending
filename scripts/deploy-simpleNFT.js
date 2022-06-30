const { ethers } = require("hardhat");
require("dotenv").config;

const { WALLET_ADDRESS } = process.env;

const ERC721_NAME = "KVN NFTs";
const ERC721_SYMBOL = "KVN";
const ERC721_BASE_URI = "https://www.ipfs.com/";
const ERC721_MINT_PRICE = ethers.utils.parseEther("0.01");
const ERC721_MAX_SUPPLY = 5;

async function deploySimpleNFT() {
  SimpleNFTFactory = await ethers.getContractFactory("SimpleNFT");
  SimpleNFT = await SimpleNFTFactory.deploy(
    ERC721_NAME,
    ERC721_SYMBOL,
    ERC721_BASE_URI,
    ERC721_MINT_PRICE,
    ERC721_MAX_SUPPLY
  );
  return SimpleNFT;
}

const main = async () => {
  // deploy lending
  let SimpleNFT = await deploySimpleNFT();
  console.log(`SimpleNFT address: ${SimpleNFT.address}`);
  // mint nft
  let txMint = await SimpleNFT.publicMint({ value: ERC721_MINT_PRICE });
  await txMint.wait();
  console.log(`Minted 1 NFT to ${WALLET_ADDRESS}`);
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.log(error);
    process.exit(1);
  });
