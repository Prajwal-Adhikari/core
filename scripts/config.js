
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
let deployed = data.polygon;
let server = data.server;

function getId(name) {
  return ethers.utils.formatBytes32String(name)
}


const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();
function getAddress(b, a) {
  return ethers.utils.solidityPack(['address','address'],
                    [a, b]);
}


async function deployToken(name) {
  console.log(`deploy token`);
  let CEToken = await hre.ethers.getContractFactory("CEToken");
  let ceToken = await CEToken.deploy("ce" + name, "ce" + name);
  let DebtToken = await hre.ethers.getContractFactory("DebtToken");
  let debtToken = await DebtToken.deploy("debt" + name, "debt" + name);
  await this.server.initPool(getId(name), [toTokenAmount(0.5), toTokenAmount(0.1),
   toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.8), toTokenAmount(0.1), toTokenAmount(0.05)],
    ceToken.address, debtToken.address);
  await ceToken.initialize(this.server.address);
  await debtToken.initialize(this.server.address);
  await this.server.changePoolStatus(getId(name), true);
}

async function main() {
  this.server = await hre.ethers.getContractAt("Pool", server);
  this.oracle = await hre.ethers.getContractAt("Oracle", data.oracle);

  // console.log("deploy token");
  // await deployToken("ETH");
  // await deployToken("MATIC");

  for(let info of Object.values(data.branches)) {
    await (await this.server.setTrustedRemote(info.chainId, getAddress(server, info.branch))).wait()
  }

  // await (await this.oracle.setPrice([getId("ETH"), getId("MATIC")], [toTokenAmount(1600), toTokenAmount(0.6)])).wait()
  console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()
