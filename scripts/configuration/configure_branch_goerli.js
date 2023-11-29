
// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
let { ethers, upgrades } = require("hardhat");

let deployed = require("../../deployed2.json");
const owner = "0x5BA85D71ef9aE0EdC180a6bf5e65F0a749f062DC";

function getAddress(b, a) {
  return ethers.utils.solidityPack(['address', 'address'],
    [a, b]);
}
const ETH = ethers.utils.formatBytes32String("ETH");
const USDC = ethers.utils.formatBytes32String("USDC");
const LZO = ethers.utils.formatBytes32String("LZO");
const AXL = ethers.utils.formatBytes32String("AXL");

async function main() {

  this.branch = await ethers.getContractAt("Branch", deployed.branches.goerli.branch);
  this.route = await ethers.getContractAt("LzRouteBranch", deployed.branches.goerli.route);
  this.adapter = await ethers.getContractAt("AdapterBranch", deployed.branches.goerli.adapter);
  this.axelar = await ethers.getContractAt("AxlRouteBranch", deployed.branches.goerli.axelar);
  this.roleManager = await ethers.getContractAt("RoleManagerBranch", deployed.branches.goerli.roleManager);


  // Grant roles
  await (await this.roleManager.grantRole(await this.roleManager.SET_ADAPTER_METHOD(), owner)).wait();
  await (await this.roleManager.grantRole(await this.roleManager.SET_BRANCH_METHOD(), owner)).wait();
  await (await this.roleManager.grantRole(await this.roleManager.SET_ROUTE_METHOD(), owner)).wait();
  await (await this.roleManager.grantRole(await this.roleManager.SET_POOL(), owner)).wait();
  await (await this.roleManager.grantRole(await this.roleManager.PROTOCOL_PAUSE(), owner)).wait();
  await (await this.roleManager.grantRole(await this.roleManager.EMERGENCY_WITHDRAW(), owner)).wait();
  await (await this.roleManager.grantRole(await this.roleManager.SWAP(), owner)).wait();
  await (await this.roleManager.grantRole(await this.roleManager.BRANCH(), deployed.branches.goerli.branch)).wait();
  await (await this.roleManager.grantRole(await this.roleManager.ADAPTER(), deployed.branches.goerli.adapter)).wait();
  await (await this.roleManager.grantRole(await this.roleManager.ROUTE(), deployed.branches.goerli.route)).wait();
  await (await this.roleManager.grantRole(await this.roleManager.ROUTE(), deployed.branches.goerli.axelar)).wait();

  await (await this.route.setTrustedRemote(deployed.chainId, getAddress(this.route.address, deployed.route))).wait();
  await (await this.branch.setPool(ETH, deployed.branches.goerli.ETH, true)).wait();
  await (await this.branch.setPool(USDC, deployed.branches.goerli.USDC, true)).wait();

  // Configure Route in Adapter
  await (await this.adapter.setRoute(LZO, this.route.address)).wait();

  // Configure Adapter in Client
  await (await this.branch.setAdapter(this.adapter.address)).wait();
  await (await this.route.setAdapter(this.adapter.address)).wait();
  await (await this.adapter.setBranch(this.branch.address)).wait();

  await (await this.axelar.setRootChainNameAddress(deployed.chain, deployed.axelar)).wait();

  // Configure Route in Adapter
  await (await this.adapter.setRoute(AXL, this.axelar.address)).wait();
  await (await this.axelar.setAdapter(this.adapter.address)).wait();

  console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()
