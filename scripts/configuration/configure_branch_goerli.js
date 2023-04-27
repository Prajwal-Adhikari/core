
// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
let { ethers, upgrades } = require("hardhat");

let deployed = require("../../deployed2.json");


function getAddress(b, a) {
  return ethers.utils.solidityPack(['address', 'address'],
    [a, b]);
}
const ETH = ethers.utils.formatBytes32String("ETH");
const LZO = ethers.utils.formatBytes32String("LZO");
const AXL = ethers.utils.formatBytes32String("AXL");

async function main() {

  this.branch = await ethers.getContractAt("Branch", deployed.branches.goerli.branch);
  this.route = await ethers.getContractAt("LzRouteBranch", deployed.branches.goerli.route);
  this.adapter = await ethers.getContractAt("AdapterBranch", deployed.branches.goerli.adapter);
  this.axelar = await ethers.getContractAt("AxlRouteBranch", deployed.branches.goerli.axelar);

  await (await this.route.setTrustedRemote(deployed.chainId, getAddress(this.route.address, deployed.route))).wait();
  await (await this.branch.setPool(ETH, deployed.branches.goerli.ETH, true)).wait();

  // Configure Route in Adapter
  await (await this.adapter.setRoute(LZO, this.route.address)).wait();

  // Configure Adapter in Client
  await (await this.branch.setAdapter(this.adapter.address)).wait();
  await (await this.route.setAdapter(this.adapter.address)).wait();
  await (await this.adapter.setBranch(this.branch.address)).wait();

  await (await this.axelar.setDestChainNameAddress(deployed.chain, deployed.axelar)).wait();

  // Configure Route in Adapter
  await (await this.adapter.setRoute(AXL, this.axelar.address)).wait();
  await (await this.axelar.setAdapter(this.adapter.address)).wait();

  console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()
