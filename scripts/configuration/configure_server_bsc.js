
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
const USDC = ethers.utils.formatBytes32String("USDC");
const LZO = ethers.utils.formatBytes32String("LZO");

const owner = "0x5BA85D71ef9aE0EdC180a6bf5e65F0a749f062DC";

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
  let ceToken =await upgrades.deployProxy(CEToken, ["ce" + name, "ce" + name, deployed.roleManager]); 
  let DebtToken = await ethers.getContractFactory("DebtToken");
  let debtToken = await upgrades.deployProxy(DebtToken, ["debt" + name, "debt" + name, deployed.roleManager]);
  await this.core.initPool(getId(name), [toTokenAmount(0.5), toTokenAmount(0.1),
  toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.8), toTokenAmount(0.1), toTokenAmount(0.1), toTokenAmount(0.15)],
    ceToken.address, debtToken.address);
  await ceToken.setCore(deployed.core, getId(name));
  await debtToken.setCore(deployed.core, getId(name));
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
  this.roleManager = await hre.ethers.getContractAt("RoleManagerPool", deployed.roleManager);

  console.log("grant Roles");
  await this.roleManager.grantRole(await this.roleManager.SET_POOL_METHOD(), owner);
  await this.roleManager.grantRole(await this.roleManager.SET_CORE_METHOD(), owner);
  await this.roleManager.grantRole(await this.roleManager.SET_ADAPTER_METHOD(), owner);
  await this.roleManager.grantRole(await this.roleManager.SET_ROUTE_METHOD(), owner);
  await this.roleManager.grantRole(await this.roleManager.SET_LIQUIDATION_METHOD(), owner);
  await this.roleManager.grantRole(await this.roleManager.SET_FEEPROVIDER_METHOD(), owner);
  await this.roleManager.grantRole(await this.roleManager.SET_CE_TOKEN_METHOD(), owner);
  await this.roleManager.grantRole(await this.roleManager.SET_CONTROLLER_METHOD(), owner);
  await this.roleManager.grantRole(await this.roleManager.SET_ORACLE_METHOD(), owner);
  await this.roleManager.grantRole(await this.roleManager.INIT_POOL(), owner);
  await this.roleManager.grantRole(await this.roleManager.POOL_STATUS(), owner);
  await this.roleManager.grantRole(await this.roleManager.PROTOCOL_PAUSE(), owner);
  await this.roleManager.grantRole(await this.roleManager.MINT_BURN_CE_DEBT_TOKEN(), deployed.liquidation);
  await this.roleManager.grantRole(await this.roleManager.MINT_BURN_CE_DEBT_TOKEN(), deployed.core);
  await this.roleManager.grantRole(await this.roleManager.POOL(), deployed.pool);
  await this.roleManager.grantRole(await this.roleManager.LIQUIDATION_MANAGER(), deployed.liquidation);
  await this.roleManager.grantRole(await this.roleManager.FEE_PROVIDER(), deployed.feeProvider);
  await this.roleManager.grantRole(await this.roleManager.CORE(), deployed.core);
  await this.roleManager.grantRole(await this.roleManager.CONTROLLER(), deployed.controller);
  await this.roleManager.grantRole(await this.roleManager.ADAPTER(), deployed.adapter);
  await this.roleManager.grantRole(await this.roleManager.ROUTE(), deployed.axelar);
  await this.roleManager.grantRole(await this.roleManager.ROUTE(), deployed.route);
  console.log("here");


  console.log("set Core address");
  await (await this.pool.setCore(deployed.core)).wait();
  console.log("set fee provider address");
  await (await this.pool.setFeeProvider(deployed.feeProvider)).wait();
  console.log("set adapter address");
  await (await this.pool.setAdapter(this.adapter.address)).wait();
  console.log("enable fee and reward");
  // await this.pool.toggleFeeEnable();

  console.log("set Route methods");
  await (await this.route.setAdapter(this.adapter.address)).wait();
  await (await this.axelar.setAdapter(this.adapter.address)).wait();

  console.log("set Oracle address");
  await (await this.core.setOracle(deployed.oracle)).wait();

  console.log("set core address");
  await this.feeProvider.setCore(deployed.core);
  console.log("set price in Oracle");
  await this.oracle.setPrice([getId("AVAX"),getId("FTM"),getId("USDC"),getId("BNB"),getId("ETH"),getId("MATIC")], [toTokenAmount(1), toTokenAmount(1), toTokenAmount(1), toTokenAmount(1), toTokenAmount(1), toTokenAmount(1)]);

  console.log("set adapter methods");
  await (await this.adapter.setPool(this.pool.address)).wait();
  await (await this.adapter.setRoute(LZO, this.route.address)).wait();
  await (await this.adapter.setRoute(AXL, deployed.axelar)).wait();

  console.log("set liquidation methods");
  await (await this.liquidation.setCore(this.core.address)).wait();
  await (await this.liquidation.setOracle(this.oracle.address)).wait();

  

  console.log(`deploy token`);
  for (let token of deployed.tokens) {
    console.log(token);
    await deployToken(token);
  }
  for (let info of Object.values(deployed.branches)) {
    console.log(`set remote ${info.chainId}`)
    await (await this.route.setTrustedRemote(info.chainId, getAddress(this.route.address, info.route))).wait()
    await (await this.route.setChainKeyID(getId(info.chainName), info.chainId)).wait();
    await (await this.axelar.setDestChainIdNameAddress(getId(info.chainName), info.chain, info.axelar)).wait();
  }




}

main().catch((error) => {
  console.error(error);
});
// test()
