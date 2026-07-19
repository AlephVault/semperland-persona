require("@nomicfoundation/hardhat-toolbox");
require("@chainlink/functions-toolkit");
require("hardhat-enquirer-plus");
require("hardhat-common-tools");
require("hardhat-blueprints");
require("hardhat-servers");
require("hardhat-method-prompts");
require("hardhat-ignition-deploy-everything");
require("hardhat-chainlink-common-blueprints");
require("hardhat-openzeppelin-common-blueprints");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  // USE AT LEAST ONE Solidity VERSION WITH OPTIMIZATION.
  // Optimizations are required for VRF and Function mocks
  // in the local networks.
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hardhat: {
      chainId: 31337
    },
    mainnet: {
      chainId: 137,
      url: 'https://polygon.drpc.org',
      mnemonic: process.env.MNEMONIC || ''
    },
    amoy: {
      chainId: 80002,
      url: 'https://polygon-amoy.drpc.org',
      mnemonic: process.env.MNEMONIC || ''
    }
  }
};
