
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

const MATIC = ethers.utils.formatBytes32String("MATIC");
const FTM = ethers.utils.formatBytes32String("FTM");
const BNB = ethers.utils.formatBytes32String("BNB");
const LZO = ethers.utils.formatBytes32String("LZO");

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
  this.route = await hre.ethers.getContractAt("LzRoutePool", deployed.route);
  this.adapter = await hre.ethers.getContractAt("AdapterPool", deployed.adapter);
  this.core = await hre.ethers.getContractAt("Core", deployed.core);
  this.oracle = await hre.ethers.getContractAt("Oracle", deployed.oracle);
  this.feeProvider = await hre.ethers.getContractAt("FeeProvider", deployed.feeProvider);
  this.liquidation = await hre.ethers.getContractAt("LiquidationManager", deployed.liquidation);
  
  console.log("set Core address");
  await (await this.server.setCore(deployed.core)).wait();
  console.log("set Cedro Token address");
  await (await this.server.setCedroToken(deployed.cedroToken)).wait();
  console.log("set Fee Provider address");
  await (await this.server.setFeeProvider(deployed.feeProvider)).wait();
  console.log("enable fee and reward");
  // await this.server.setFeeRewardStatus(true, true);

  console.log("set Route methods");
  await (await this.route.setTrustedRemote(deployed.branches.ftm.chainId, getAddress(this.route.address, deployed.branches.ftm.route))).wait();
  await (await this.route.setAdapter(this.adapter.address)).wait();
  await (await this.route.setChainNameID(FTM, deployed.branches.ftm.chainId)).wait();

  console.log("set Server address");
  await (await this.core.setPool(deployed.server)).wait();
  console.log("set Oracle address");
  await (await this.core.setOracle(deployed.oracle)).wait();

  console.log("init FTM pool");
  await (await core.initPool(FTM, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.05), toTokenAmount(0.05)], deployed.branches.ftm.ceToken, deployed.branches.ftm.debtToken)).wait();
  console.log("change Pool status");
  await (await core.changePoolStatus(getId("FTM"), true)).wait();

  console.log("change core address");
  await this.feeProvider.setCore(deployed.core);
  console.log("set price in Oracle");
  await this.oracle.setPrice([MATIC, FTM, BNB], [toTokenAmount(1), toTokenAmount(1), toTokenAmount(1)]);

  console.log("set adapter methods");
  await (await this.adapter.setPool(this.server.address)).wait();
  await (await this.adapter.setRoute(LZO, this.route.address)).wait();
  
  console.log("set liquidation methods");
  await (await this.liquidation.setCore(this.core.address)).wait();
  await (await this.liquidation.setOracle(this.oracle.address)).wait();

  

  await (await this.server.setAdapter(this.adapter.address)).wait();



}

main().catch((error) => {
  console.error(error);
});
// test()
