require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
const PRIVATE_KEY = process.env.PRIVATE_KEY;
/** @type import('hardhat/config').HardhatUserConfig */
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});
module.exports = {
  solidity: "0.8.17",

  settings: { optimizer: { enabled: true, runs: 200, details: { yul: false }, }, },

  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    goerli: {
      url: `https://endpoints.omniatech.io/v1/eth/goerli/public`,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    ftm: {
      url: `https://fantom-testnet.public.blastapi.io`,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    arbitrum: {
      url: `https://goerli-rollup.arbitrum.io/rpc`,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    avax: {
      url: `https://api.avax-test.network/ext/bc/C/rpc`,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    mainnet: {
      url: `https://jsonrpc.maiziqianbao.net`,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/f55e80a3523b48feb3ef8e4a0c9f5bcc`,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    clover: {
      url: `https://rpc.clover.finance`,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    polygon: {
      url: `https://matic-mumbai.chainstacklabs.com`,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    bsc: {
      url: `https://bsc-testnet-rpc.allthatnode.com`,
      accounts: [`0x${PRIVATE_KEY}`],
      gas: 4000000
    }
  }
};
