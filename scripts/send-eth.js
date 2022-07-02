const { ethers } = require("hardhat");
require("dotenv").config;

const { RPC_SERVER, RECEIVER_ADDRESS } = process.env;
const ETH_TO_SEND = "20";

const main = async () => {
  let provider = new ethers.providers.JsonRpcProvider(RPC_SERVER);
  const wallet = new ethers.Wallet(SUPPLY_PRIVATE_KEY, provider);
  console.log(wallet);
  let sendEthTx = {
    to: RECEIVER_ADDRESS,
    value: ethers.utils.parseEther(ETH_TO_SEND),
  };
  let tx = await wallet.sendTransaction(sendEthTx);
  let txReceipt = await tx.wait();
  console.log(txReceipt);
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.log(error);
    process.exit(1);
  });
