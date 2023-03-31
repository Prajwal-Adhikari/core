
// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const owner = "0x5BA85D71ef9aE0EdC180a6bf5e65F0a749f062DC";

let BN = require("bignumber.js");
let fs = require("fs")
 
const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

let deployed = require("../../deployed2.json");
let data = deployed.branches.ftm;


async function main() {
  console.log(`deploy token`);
  let Token = await hre.ethers.getContractFactory("ERC20Mock");
  this.ftm = await Token.deploy("testFTM", "testFTM");
  this.usdc =  await Token.deploy("testUSDC", "testUSDC");

  data["FTM"] = this.ftm.address;
  data["USDC"] = this.usdc.address;
  console.log("FTM", data["FTM"], "USDC", data["USDC"]);

  console.log("deploy branch")

  let Branch = await hre.ethers.getContractFactory("Branch");
  this.branch = (await hre.upgrades.deployProxy(Branch,[data.endpoint, data.chainId, deployed.serverId, 300000]));
  data["branch"] = this.branch.address;
  console.log("Branch", data["branch"]);

  await (await this.ftm.mint(owner, toTokenAmount(1000000))).wait();
  console.log("mint done");
  await (await this.ftm.approve(data.branch, toTokenAmount(1000000))).wait();
  console.log("approve done");
  await (await this.usdc.mint(owner, toTokenAmount(1000000))).wait();
  console.log("mint done");
  await (await this.usdc.approve(data.branch, toTokenAmount(1000000))).wait();
  console.log("approve done");

  console.log("config");


  fs.writeFileSync("./deployed2.json", JSON.stringify(deployed, null, 4))
}

main().catch((error) => {
  console.error(error);
});
// test()
