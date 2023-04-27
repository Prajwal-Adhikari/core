
// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

let BN = require("bignumber.js");
let { ethers } = require("hardhat");

const AXL = ethers.utils.formatBytes32String("AXL");
const LZO = ethers.utils.formatBytes32String("LZO");

const toTokenAmount = (amount, decimals = 18) => {
  return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

let deployed = require("../../deployed2.json");

function getId(name) {
  return ethers.utils.formatBytes32String(name)
}

function getAddress(b, a) {
  return ethers.utils.solidityPack(['address','address'],
                    [a, b]);
}

async function deployToken(name) {
  console.log(`deploy token`);
  let CEToken = await ethers.getContractFactory("CEToken");
  let ceToken = await CEToken.deploy("ce" + name, "ce" + name);
  let DebtToken = await ethers.getContractFactory("DebtToken");
  let debtToken = await DebtToken.deploy("debt" + name, "debt" + name);
  await this.core.initPool(getId(name), [toTokenAmount(0.5), toTokenAmount(0.1),
  toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.8), toTokenAmount(0.1), toTokenAmount(0.05), toTokenAmount(0.05)],
    ceToken.address, debtToken.address);
  await ceToken.initialize(deployed.core, deployed.liquidation);
  await debtToken.initialize(deployed.core, deployed.liquidation);
  await this.core.changePoolStatus(getId(name), true);
  console.log(name, ceToken.address, debtToken.address);
}

async function main() {

  this.pool = await hre.ethers.getContractAt("Pool", deployed.pool);
  this.route = await hre.ethers.getContractAt("LzRoutePool", deployed.route);
  this.axelar = await hre.ethers.getContractAt("AxlRoutePool", deployed.axelar);
  this.adapter = await hre.ethers.getContractAt("AdapterPool", deployed.adapter);
  this.core = await hre.ethers.getContractAt("Core", deployed.core);
  this.oracle = await hre.ethers.getContractAt("Oracle", deployed.oracle);
  this.feeProvider = await hre.ethers.getContractAt("FeeProvider", deployed.feeProvider);
  this.liquidation = await hre.ethers.getContractAt("LiquidationManager", deployed.liquidation);

  // console.log("set Core address");
  // await (await this.pool.setCore(deployed.core)).wait();
  // console.log("set fee provider address");
  // await (await this.pool.setFeeProvider(deployed.feeProvider)).wait();
  // console.log("set adapter address");
  // await (await this.pool.setAdapter(this.adapter.address)).wait();
  // console.log("enable fee and reward");
  // // await this.pool.toggleFeeEnable();

  // console.log("set Route methods");
  // await (await this.route.setAdapter(this.adapter.address)).wait();
  // await (await this.axelar.setAdapter(this.adapter.address)).wait();

  // console.log("set Pool address");
  // await (await this.core.setPool(deployed.pool)).wait();
  // console.log("set Oracle address");
  // await (await this.core.setOracle(deployed.oracle)).wait();

  // console.log("set core address");
  // await this.feeProvider.setCore(deployed.core);
  // console.log("set price in Oracle");
  // await this.oracle.setPrice([getId("AVAX"),getId("FTM"),getId("USDC"),getId("BNB"),getId("ETH"),getId("MATIC")], [toTokenAmount(1), toTokenAmount(1), toTokenAmount(1), toTokenAmount(1), toTokenAmount(1), toTokenAmount(1)]);

  // console.log("set adapter methods");
  // await (await this.adapter.setPool(this.pool.address)).wait();
  // await (await this.adapter.setRoute(LZO, this.route.address)).wait();
  // await (await this.adapter.setRoute(AXL, deployed.axelar)).wait();

  // console.log("set liquidation methods");
  // await (await this.liquidation.setCore(this.core.address)).wait();
  // await (await this.liquidation.setOracle(this.oracle.address)).wait();

  

  // console.log(`deploy token`);
  // for (let token of deployed.tokens) {
  //   console.log(token);
  //   await deployToken(token);
  // }
  for (let info of Object.values(deployed.branches)) {
    console.log(`set remote ${info.chainId}`)
    await (await this.route.setTrustedRemote(info.chainId, getAddress(this.route.address, info.route))).wait()
    await (await this.route.setChainNameID(getId(info.chainName), info.chainId)).wait();
    await (await this.axelar.setDestChainNameAddress(getId(info.chainName), info.chain, info.axelar)).wait();
  }

}

main().catch((error) => {
  console.error(error);
});
// test()
