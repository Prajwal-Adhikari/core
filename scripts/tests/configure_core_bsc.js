
// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

let BN = require("bignumber.js");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}
function getId(name) {
    return ethers.utils.formatBytes32String(name)
  }

let deployed = require("../../deployed2.json");


async function main() {
    this.core = await hre.ethers.getContractAt("Core", deployed.core);

    // console.log("set Server address");
    // await (await this.core.setPool(deployed.server)).wait();
    // console.log("set Oracle address");
    // await (await this.core.setOracle(deployed.oracle)).wait();

    console.log("init FTM pool");
    await (await core.initPool(getId("FTM"), [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.05)], deployed.branches.ftm.ceToken, deployed.branches.ftm.debtToken)).wait();
    console.log("change Pool status");
    await (await core.changePoolStatus(getId("FTM"), true)).wait();

    console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()