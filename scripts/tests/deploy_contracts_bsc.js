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
    const FeeProvider = await ethers.getContractFactory("FeeProvider");
    this.feeProvider = await upgrades.deployProxy(FeeProvider, []);
    deployed["feeProvider"] = this.feeProvider.address;
    console.log("deployed Fee Provider", deployed["feeProvider"]);

    const Oracle = await ethers.getContractFactory("Oracle");
    this.oracle = await Oracle.deploy();
    deployed["oracle"] = this.oracle.address;
    console.log("deployed Oracle", deployed["oracle"]);
    fs.writeFileSync("./deployed2.json", JSON.stringify(deployed, null, 4))

}

main().catch((error) => {
  console.error(error);
});
// test()

