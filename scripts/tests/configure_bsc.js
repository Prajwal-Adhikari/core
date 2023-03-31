
// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

let BN = require("bignumber.js");

const MATIC = ethers.utils.formatBytes32String("MATIC");
const FTM = ethers.utils.formatBytes32String("FTM");
const BNB = ethers.utils.formatBytes32String("BNB");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

let deployed = require("../../deployed2.json");


async function main() {
    this.oracle = await hre.ethers.getContractAt("Oracle", deployed.oracle);
    this.feeProvider = await hre.ethers.getContractAt("FeeProvider", deployed.feeProvider);
    await this.feeProvider.setCore(deployed.core);
    await this.oracle.setPrice([MATIC, FTM, BNB], [toTokenAmount(1), toTokenAmount(1), toTokenAmount(1)]);
    console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()