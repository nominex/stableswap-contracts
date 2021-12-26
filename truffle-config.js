
module.exports = {
  networks: {
    development: {
      host: "127.0.0.1",
      port: 7545,
      network_id: "97",
      gas: 6721975,
    }
  },

  // Set default mocha options here, use special reporters etc.
  mocha: {
    useColors: true,
    timeout: 100000,
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: "=0.5.16", // A version or constraint - Ex. "^0.5.0"
      settings: {
        optimizer: {
          enabled: true,
          runs: 9999999,
        },
        evmVersion: 'istanbul',
      },
    },
  },
}
