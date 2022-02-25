let mnemonic = "elbow reform bench purpose owner dinner sad then cost fatigue where humble";

module.exports = {
  networks: {
    development: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*",
      gas: 9999999,
    },
  },
  compilers: {
    solc: {
      version: "^0.8.0",
    },
  },
};
