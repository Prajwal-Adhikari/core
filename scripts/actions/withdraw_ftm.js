
let deployed = require("../../deployed2.json");
const { ethers } = require("hardhat");
const FTM = ethers.utils.formatBytes32String("FTM");
const LZO = ethers.utils.formatBytes32String("LZO");

const owner = "0x5BA85D71ef9aE0EdC180a6bf5e65F0a749f062DC";

let BN = require("bignumber.js");


const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

async function main() {
  this.pool = await hre.ethers.getContractAt("Pool", deployed.pool);
  this.route = await hre.ethers.getContractAt("LzRoutePool", deployed.route);
  let fees = await this.route.estimateFees(FTM, 1);
  console.log(fees);

  await this.pool.withdraw(FTM, FTM, toTokenAmount(100), ethers.utils.hexZeroPad(ethers.utils.getAddress( owner ), 32),LZO,0, {value: fees});

  console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()
// test()




        

   