
// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
let { ethers, upgrades } = require("hardhat");

let deployed = require("../../deployed2.json");


function getAddress(b, a) {
  return ethers.utils.solidityPack(['address','address'],
                    [a, b]);
}
const FTM = ethers.utils.formatBytes32String("FTM");
const LZO = ethers.utils.formatBytes32String("LZO");

async function main() {

  this.client = await ethers.getContractAt("Branch", deployed.branches.ftm.branch);
  this.route = await ethers.getContractAt("LzRouteBranch", deployed.branches.ftm.route);
  this.adapter = await ethers.getContractAt("AdapterBranch", deployed.branches.ftm.adapter);

  await(await this.route.setTrustedRemote(deployed.serverId, getAddress(this.route.address, deployed.route))).wait();
  await(await this.client.setPool(FTM, deployed.branches.ftm.FTM, true)).wait();

  // Configure Route in Adapter
  await(await this.adapter.setRoute(LZO, this.route.address)).wait();

  // Configure Adapter in Client
  await(await this.client.setAdapter(this.adapter.address)).wait();
  await(await this.route.setAdapter(this.adapter.address)).wait();
  await(await this.adapter.setBranch(this.client.address)).wait();

  console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()
