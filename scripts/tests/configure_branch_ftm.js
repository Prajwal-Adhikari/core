
// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

let deployed = require("../../deployed2.json");


function getAddress(b, a) {
  return ethers.utils.solidityPack(['address','address'],
                    [a, b]);
}
const FTM = ethers.utils.formatBytes32String("FTM");

async function main() {

    this.client = await hre.ethers.getContractAt("Branch", deployed.branches.ftm.branch);
    await this.client.setTrustedRemote(deployed.serverId, getAddress(this.client.address, deployed.server))
    await this.client.setPool(FTM, deployed.branches.ftm.FTM, true);

    console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()
