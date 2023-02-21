// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
let fs = require("fs")
let deployed = require("../deployed.json");

async function main() {
  console.log("deploy");
  let Oracle = await hre.ethers.getContractFactory("Oracle");
  let Server = await hre.ethers.getContractFactory("Pool");

  this.oracle = await Oracle.deploy();
  this.server = await Server.deploy(deployed.endpoint, deployed.treasury, deployed.serverId);
  await this.server.setOracle(this.oracle.address)

  deployed.server = this.server.address
  deployed.oracle = this.oracle.address;
  fs.writeFileSync("./deployed.json", JSON.stringify(deployed, null, 4))
  console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()
