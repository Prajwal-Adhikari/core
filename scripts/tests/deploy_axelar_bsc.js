// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers, upgrades } = require("hardhat")
let fs = require("fs")
let deployed = require("../../deployed2.json");


const FTM = ethers.utils.formatBytes32String("FTM");
const AXL = ethers.utils.formatBytes32String("AXL");
async function main() {
console.log("deploy");
this.server = await ethers.getContractAt("Pool", deployed.server);
this.route = await ethers.getContractAt("LzRoutePool", deployed.route);
this.adapter = await ethers.getContractAt("AdapterPool", deployed.adapter);
this.axelar = await ethers.getContractAt("AxlRoutePool", deployed.axelar);


// let Axelar = await ethers.getContractFactory("AxlRoutePool");
// this.axelar = await upgrades.deployProxy(Axelar, [deployed.gateway, deployed.gasservice]);

// deployed.axelar = this.axelar.address


await(await this.axelar.setDestChainNameAddress(FTM, deployed.branches.ftm.chain,deployed.branches.ftm.axelar)).wait();


// Configure Route in Adapter
await(await this.adapter.setRoute(AXL, deployed.axelar)).wait();
await(await this.axelar.setAdapter(deployed.adapter)).wait();



console.log("deployed axelar", this.axelar.address);

fs.writeFileSync("./deployed2.json", JSON.stringify(deployed, null, 4))
}

main().catch((error) => {
  console.error(error);
});
// test()
