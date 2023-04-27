
// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers, upgrades } = require("hardhat");
const owner = "0x5BA85D71ef9aE0EdC180a6bf5e65F0a749f062DC";

let BN = require("bignumber.js");
let fs = require("fs")
 
const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

let deployed = require("../../deployed2.json");
let data = deployed.branches.bsc;


async function main() {
  console.log(`deploy token`);
  let Token = await ethers.getContractFactory("ERC20Mock");
  this.bnb = await Token.deploy("testBNB", "testBNB");
  this.usdc =  await Token.deploy("testUSDC", "testUSDC");

  data["BNB"] = this.bnb.address;
  data["USDC"] = this.usdc.address;
  console.log("BNB", data["BNB"], "USDC", data["USDC"]);

  console.log("deploy branch")

  let Branch = await ethers.getContractFactory("Branch");
  this.branch = (await upgrades.deployProxy(Branch,[]));
  data["branch"] = this.branch.address;
  console.log("Branch", data["branch"]);

  // Client Adapter
  const Adapter = await ethers.getContractFactory("AdapterBranch");
  this.adapter = await upgrades.deployProxy(Adapter, []);

  data["adapter"] = this.adapter.address;
  console.log("Adapter", data["adapter"]);
  
  // Client LZ Route
  const Route = await ethers.getContractFactory("LzRouteBranch");
  this.route = await upgrades.deployProxy(Route, [data.endpoint, data.chainId, deployed.chainId, 350000]);

  data["route"] = this.route.address;
  console.log("Route", data["route"]);

  // Client AXL Route
  let Axelar = await ethers.getContractFactory("AxlRouteBranch");
  this.axelar = await upgrades.deployProxy(Axelar, [data.gateway, data.gasservice]);

  data["axelar"] = this.axelar.address;
  console.log("Axelar", data["axelar"]);
  

  await (await this.bnb.mint(owner, toTokenAmount(1000000))).wait();
  console.log("mint done");
  await (await this.bnb.approve(data.branch, toTokenAmount(1000000))).wait();
  console.log("approve done");
  await (await this.usdc.mint(owner, toTokenAmount(1000000))).wait();
  console.log("mint done");
  await (await this.usdc.approve(data.branch, toTokenAmount(1000000))).wait();
  console.log("approve done");

  console.log("complete");

  fs.writeFileSync("./deployed2.json", JSON.stringify(deployed, null, 4))
}

main().catch((error) => {
  console.error(error);
});
// test()
