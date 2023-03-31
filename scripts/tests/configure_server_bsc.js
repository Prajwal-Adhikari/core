
// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const owner = "0x892a2b7cF919760e148A0d33C1eb0f44D3b383f8";

let BN = require("bignumber.js");
let fs = require("fs")
let { ethers } = require("hardhat");


const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

let deployed = require("../../deployed2.json");

function getId(name) {
  return ethers.utils.formatBytes32String(name)
}


const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();
function getAddress(b, a) {
  return ethers.utils.solidityPack(['address','address'],
                    [a, b]);
}

async function main() {

    this.server = await hre.ethers.getContractAt("Pool", deployed.server);
   
    console.log("set Core address");
    await (await this.server.setCore(deployed.core)).wait();
    console.log("set Cedro Token address");
    await (await this.server.setCedroToken(deployed.cedroToken)).wait();
    console.log("set Fee Provider address");
    await (await this.server.setFeeProvider(deployed.feeProvider)).wait();
    console.log("enable fee and reward");
    await this.server.setFeeRewardStatus(true, true);

    await this.server.setTrustedRemote(deployed.branches.ftm.chainId, getAddress(this.server.address, deployed.branches.ftm.branch))

    console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()
