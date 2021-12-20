const HDWalletProvider = require('@truffle/hdwallet-provider')
const fs = require('fs')
const path = require('path')
const localMnemonic = fs.readFileSync(path.join(__dirname, './.secret/local.secret')).toString().trim()

module.exports = {
  contracts_directory: path.join(__dirname, 'contracts'),
  networks: {
    local: {
      network_id: '*',
      provider: () => new HDWalletProvider(localMnemonic, `http://127.0.0.1:7545`),
      confirmations: 0,
      deploymentPollingInterval: 1000,
      skipDryRun: true,
      timeoutBlocks: 4000, 
      networkCheckTimeout : 100,
    },
  },

  // Set default mocha options here, use special reporters etc.
  mocha: {
    useColors: true,
    timeout: 100000
  },

  plugins: [
    "truffle-plugin-debugger"
  ],

  // Configure your compilers
  compilers: {
    solc: {
      version: "=0.5.16", // A version or constraint - Ex. "^0.5.0"
      settings: {
        optimizer: {
          enabled: true,
          runs: 1000,   // Optimize for how many times you intend to run the code
        },
        evmVersion: 'istanbul'
      },
    }
  }
}