/**
 * @type import('hardhat/config').HardhatUserConfig
 */

require("dotenv").config();
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-gas-reporter");

const {
  RPC_SERVER,
  GOERLI_SERVER,
  PRIVATE_KEY,
  ETHERSCAN_KEY,
  COINMARKETCAP_API,
} = process.env;

module.exports = {
  solidity: {
    compilers: [
      { version: "0.8.10" },
      { version: "0.8.0" },
      { version: "0.7.0" },
    ],
  },
  defaultNetwork: "ganache",
  networks: {
    hardhat: {},
    ganache: {
      url: RPC_SERVER,
      accounts: [`${PRIVATE_KEY}`],
    },
    goerli: {
      url: GOERLI_SERVER,
      accounts: [`${PRIVATE_KEY}`],
    },
  },
  etherscan: {
    apiKey: ETHERSCAN_KEY,
  },
  gasReporter: {
    enabled: true,
    outputFile: "gasReporter.txt",
    noColors: true,
    currency: "USD",
    coinmarketcap: COINMARKETCAP_API,
  },
};
