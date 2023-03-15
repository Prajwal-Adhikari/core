
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

let data = require("../deployed.json");
let deployed = data.branches.avax;
let server = data.server;

function getId(name) {
  return ethers.utils.formatBytes32String(name)
}


const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();
function getAddress(b, a) {
  return ethers.utils.solidityPack(['address','address'],
                    [a, b]);
}

async function main() {
  console.log(`deploy token`);
  let Token = await hre.ethers.getContractFactory("ERC20Mock");
  this.avax = await Token.deploy("testAVAX", "testAVAX");
  this.usdc = await Token.deploy("testUSDC", "testUSDC");

  deployed["AVAX"] = this.avax.address;
  deployed["USDC"] = this.usdc.address;

  console.log("deploy branch")

  let Branch = await hre.ethers.getContractFactory("Branch");
  this.branch = await Branch.deploy(deployed.endpoint, deployed.chainId, data.serverId);
  deployed["branch"] = this.branch.address;

  await (await this.avax.mint(owner, toTokenAmount(1000000))).wait();
  await (await this.avax.approve(deployed.branch, toTokenAmount(1000000))).wait();
  await (await this.usdc.mint(owner, toTokenAmount(1000000))).wait();
  await (await this.usdc.approve(deployed.branch, toTokenAmount(1000000))).wait();

  console.log("config");

  await (await this.branch.setTrustedRemote(data.serverId, getAddress(deployed.branch, server))).wait()
  await (await this.branch.setPool(getId("AVAX"), deployed.AVAX, true)).wait()
  await (await this.branch.setPool(getId("USDC"), deployed.USDC, true)).wait()
  console.log("complete");

  fs.writeFileSync("./deployed.json", JSON.stringify(data, null, 4))
}

main().catch((error) => {
  console.error(error);
});
// test()
