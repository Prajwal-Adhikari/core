// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers, upgrades } = require("hardhat")
let fs = require("fs")
let deployed = require("../../deployed2.json");


const AXL = ethers.utils.formatBytes32String("AXL");
async function main() {
console.log("deploy");
this.client = await ethers.getContractAt("Branch", deployed.branches.ftm.branch);
this.route = await ethers.getContractAt("LzRouteBranch", deployed.branches.ftm.route);
this.adapter = await ethers.getContractAt("AdapterBranch", deployed.branches.ftm.adapter);
this.axelar = await ethers.getContractAt("AxlRouteBranch", deployed.branches.ftm.axelar);


// let Axelar = await ethers.getContractFactory("AxlRouteBranch");
// this.axelar = await upgrades.deployProxy(Axelar, [deployed.branches.ftm.gateway, deployed.branches.ftm.gasservice]);

// deployed.branches.ftm.axelar = this.axelar.address



await(await this.axelar.setDestChainNameAddress(deployed.chain, deployed.axelar)).wait();


// Configure Route in Adapter
await(await this.adapter.setRoute(AXL, deployed.branches.ftm.axelar)).wait();
await(await this.axelar.setAdapter(deployed.branches.ftm.adapter)).wait();



console.log("deployed axelar", this.axelar.address);

fs.writeFileSync("./deployed2.json", JSON.stringify(deployed, null, 4))
}

main().catch((error) => {
  console.error(error);
});
// test()
