// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
let fs = require("fs")
let deployed = require("../../deployed2.json");

let BN = require("bignumber.js");

const toTokenAmount = (amount, decimals = 18) => {
  return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

async function main() {
    console.log("deploy");

    console.log(`deploy token`);
    let name = "FTM"
    let CEToken = await hre.ethers.getContractFactory("CEToken");
    let ceToken = await CEToken.deploy("ce" + name, "ce" + name);
    let DebtToken = await hre.ethers.getContractFactory("DebtToken");
    let debtToken = await DebtToken.deploy("debt" + name, "debt" + name);
    let data = deployed.branches.ftm
    data.ceToken = ceToken.address;
    data.debtToken = debtToken.address;
   
    console.log("deployed ce and debt Tokens", data.ceToken, data.debtToken);

    const Cedro = await hre.ethers.getContractFactory("CedroToken");
    this.cedro = await Cedro.deploy(toTokenAmount(1e9));

    deployed["cedroToken"] = this.cedro.address;
    console.log("deployed cedro Token", deployed["cedroToken"]);

    
    
    // let Token = await hre.ethers.getContractFactory("ERC20Mock");
    // this.ftm = await Token.deploy("testFTM", "testFTM");
    // this.usdc =  await Token.deploy("testUSDC", "testUSDC");

    // data["FTM"] = this.ftm.address;
    // data["USDC"] = this.usdc.address;
    // console.log("FTM", data["FTM"], "USDC", data["USDC"]);
    fs.writeFileSync("./deployed2.json", JSON.stringify(deployed, null, 4))

}

main().catch((error) => {
  console.error(error);
});
// test()
