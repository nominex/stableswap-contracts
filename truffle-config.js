const Wallet = require('ethereumjs-wallet').default;
const ProviderEngine = require("@trufflesuite/web3-provider-engine");
const WalletSubprovider = require('@trufflesuite/web3-provider-engine/subproviders/wallet.js');
const Web3Subprovider = require("@trufflesuite/web3-provider-engine/subproviders/provider.js");
const web3 = require("web3");
const nconf = require("nconf");
require('ts-node/register');

nconf.argv().env().file({ file: './.config.json' });
function provider(url) {
  nconf.required(["DEPLOYER_PRIVATE_KEY"]);
  const privateKey = nconf.get("DEPLOYER_PRIVATE_KEY");
  const wallet = new Wallet(Buffer.from(privateKey, "hex"));
  const engine = new ProviderEngine();
  engine.addProvider(new WalletSubprovider(wallet, {}));
  engine.addProvider(new Web3Subprovider(new web3.providers.HttpProvider(url, { keepAlive: true, timeout: 1000000 })));
  engine.on = (block) => { }
  engine.start();
  return engine;
}

module.exports = {
  networks: {
    development: {
      host: "127.0.0.1",
      port: 9545,
      network_id: "5777",
      gas: 6721975,
    },
    testnet: {
      network_id: "97",
      provider: () => provider("https://data-seed-prebsc-1-s1.binance.org:8545/"),
      networkCheckTimeout: 1000000,
      gasPrice: 10000000000
    },
    mainnet: {
      network_id: "56",
      provider: () => provider("https://bsc-dataseed4.binance.org/"),
      networkCheckTimeout: 1000000,
      gasPrice: 5000000000
    }
  },

  // Set default mocha options here, use special reporters etc.
  mocha: {
    reporter: "spec",
    reporterOption: "test-ss/**/*.spec.js",
    spec: "test-ss/**/*.spec.js",
    test: "test-ss/**/*.spec.js",
    useColors: true,
    timeout: 100000,
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: "0.8.15", // A version or constraint - Ex. "^0.5.0"
      settings: {
        optimizer: {
          enabled: true,
          runs: 999999,
        },
        evmVersion: 'istanbul',
      },
    },
  },
  plugins: [
    "truffle-plugin-verify",
    "truffle-plugin-solhint"
  ],

  api_keys: {
    etherscan: nconf.get("ETHERSCAN_API_KEY"),
    bscscan: nconf.get("ETHERSCAN_API_KEY")
  }
};
