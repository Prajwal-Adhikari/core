// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers, upgrades } = require("hardhat")
let fs = require("fs")
let deployed = require("../../deployed2.json");




async function main() {
console.log("deploy", ethers.utils.formatBytes32String("BNB"),  ethers.utils.formatBytes32String("USDC"));

const RoleManager = await ethers.getContractFactory("RoleManagerPool");
this.roleManager = await upgrades.deployProxy(RoleManager, []);
deployed.roleManager = this.roleManager.address
console.log("deployed roleManager", this.roleManager.address);

let Pool = await ethers.getContractFactory("Pool");
this.pool = await upgrades.deployProxy(Pool,[this.roleManager.address,this.roleManager.address]);
deployed.pool = this.pool.address
console.log("deployed pool", this.pool.address);

const Core = await ethers.getContractFactory("Core");
this.core = await upgrades.deployProxy(Core,[deployed.treasury, this.roleManager.address]);
deployed.core = this.core.address
console.log("deployed core", this.core.address);

const Adapter = await ethers.getContractFactory("AdapterPool");
this.adapter = await upgrades.deployProxy(Adapter, [this.roleManager.address]);
deployed.adapter = this.adapter.address;
console.log("deployed adapter", this.adapter.address);

const LzRoute = await ethers.getContractFactory("LzRoutePool");
this.route = await upgrades.deployProxy(LzRoute, [deployed.endpoint, deployed.chainId, 200000,this.roleManager.address]);
deployed.route = this.route.address;
console.log("deployed route", this.route.address);

const FeeProvider = await ethers.getContractFactory("FeeProvider");
this.feeProvider = await upgrades.deployProxy(FeeProvider, [this.roleManager.address]);
deployed["feeProvider"] = this.feeProvider.address;
console.log("deployed Fee Provider", deployed["feeProvider"]);

const Oracle = await ethers.getContractFactory("Oracle");
this.oracle = await upgrades.deployProxy(Oracle, [this.roleManager.address]);
deployed["oracle"] = this.oracle.address;
console.log("deployed Oracle", deployed["oracle"]);

const LiquidationManager = await ethers.getContractFactory("LiquidationManager");
this.liquidation = await upgrades.deployProxy(LiquidationManager,[this.roleManager.address]);
deployed.liquidation = this.liquidation.address
console.log("deployed liquidation", this.liquidation.address);

const Axelar = await ethers.getContractFactory("AxlRoutePool");
this.axelar = await upgrades.deployProxy(Axelar, [deployed.gateway, deployed.gasservice, this.roleManager.address, "binance"]);
deployed.axelar = this.axelar.address
console.log("deployed axelar", this.axelar.address);

const Controller = await ethers.getContractFactory("Controller");
this.controller = await upgrades.deployProxy(Controller, [ this.roleManager.address]);
deployed.controller = this.controller.address
console.log("deployed controller", this.controller.address);

fs.writeFileSync("./deployed2.json", JSON.stringify(deployed, null, 4))
}

main().catch((error) => {
  console.error(error);
});
// test()
