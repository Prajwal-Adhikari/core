// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
let fs = require("fs")
let deployed = require("../../deployed2.json");



async function main() {
  console.log("deploy");
  let Server = await hre.ethers.getContractFactory("Pool");
  this.server = await hre.upgrades.deployProxy(Server,[deployed.endpoint, deployed.serverId, 300000]);
  deployed.server = this.server.address
  console.log("deployed server", this.server.address);

  let Core = await hre.ethers.getContractFactory("Core");
  this.core = await hre.upgrades.deployProxy(Core,[deployed.treasury]);
  deployed.core = this.core.address
  console.log("deployed core", this.core.address);

  fs.writeFileSync("./deployed2.json", JSON.stringify(deployed, null, 4))
}

main().catch((error) => {
  console.error(error);
});
// test()
