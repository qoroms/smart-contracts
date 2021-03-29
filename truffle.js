const connectionConfig = require('frg-ethereum-runners/config/network_config.json');
const HDWalletProvider = require('truffle-hdwallet-provider');

require('dotenv').config();

module.exports = {
  networks: {
    ganacheUnitTest: connectionConfig.ganacheUnitTest,
    gethUnitTest: connectionConfig.gethUnitTest,
    testrpcCoverage: connectionConfig.testrpcCoverage,
    rinkeby: {
      provider: () =>
        new HDWalletProvider(
          process.env.MNEMONIC,
          process.env.RINKEBY_PROVIDER,
          1,
          2
        ),
      network_id: 4,
      gas: 6500000,
      gasPrice: 2000000000
    },
    ropsten: {
      provider: () =>
        new HDWalletProvider(
          process.env.MNEMONIC,
          process.env.ROPSTEN_PROVIDER,
          1,
          2
        ),
      network_id: 3,
      gas: 3500000,
      gasPrice: 100000000000
    },
    bsc: {
      provider: () =>
        new HDWalletProvider(
          process.env.MNEMONIC,
          `https://bsc-dataseed1.binance.org`,
          16,
          19
        ),
      network_id: 56,
      confirmations: 10,
      timeoutBlocks: 200,
      skipDryRun: true
    },
    mainnet: {
      ref: 'mainnet-prod',
      network_id: 1,
      provider: () =>
        new HDWalletProvider(
          process.env.MNEMONIC,
          process.env.MAINNET_PROVIDER,
          16,
          19
        ),
      gas: 6500000,
      gasPrice: 140000000000
    },
    matic: {
      provider: () =>
        new HDWalletProvider(
          process.env.MNEMONIC,
          'https://rpc-mainnet.matic.network',
          1,
          2
        ),
      network_id: 137,
      gas: 7000000,
      gasPrice: 10000000000, // 10 gwei
      skipDryRun: true
    }
  },
  mocha: {
    enableTimeouts: false,
    reporter: 'eth-gas-reporter',
    reporterOptions: {
      currency: 'USD'
    }
  },
  compilers: {
    solc: {
      version: '0.5.0',
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }
  },
  plugins: ['truffle-plugin-verify'],
  api_keys: {
    etherscan: process.env.ETHERSCAN_API_KEY
  }
};
