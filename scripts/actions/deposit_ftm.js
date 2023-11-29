let deployed = require("../../deployed2.json");
const MATIC = ethers.utils.formatBytes32String("MATIC");
const USDC = ethers.utils.formatBytes32String("USDC");
const LZO = ethers.utils.formatBytes32String("LZO");
const owner = "0x5BA85D71ef9aE0EdC180a6bf5e65F0a749f062DC"; 

let BN = require("bignumber.js");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

async function main() {
  this.branch = await hre.ethers.getContractAt("Branch", deployed.branches.polygon.branch);
  this.route = await hre.ethers.getContractAt("LzRouteBranch", deployed.branches.polygon.route);
  this.matic = await hre.ethers.getContractAt("ERC20Mock", deployed.branches.polygon.MATIC);
  this.usdc = await hre.ethers.getContractAt("ERC20Mock", deployed.branches.polygon.USDC);
  let fees = await this.route.estimateFees(1,0);
  console.log(fees);
  let balance_ftm_client = await this.matic.balanceOf(this.branch.address);
  console.log("Before balance of matic pool", balance_ftm_client.toString(), this.branch.address);
  balance_ftm_client = await this.matic.balanceOf(owner);
  console.log("Before balance of owner", balance_ftm_client.toString(), owner, USDC);
  await(await this.branch.depositRequest(MATIC, toTokenAmount(500), LZO, 0, {value: fees})).wait();
  console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()
// test()




        

   