
let deployed = require("../../deployed2.json");
const FTM = ethers.utils.formatBytes32String("FTM");
const LZO = ethers.utils.formatBytes32String("LZO");
const owner = "0x5BA85D71ef9aE0EdC180a6bf5e65F0a749f062DC";

let BN = require("bignumber.js");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

async function main() {
  this.branch = await hre.ethers.getContractAt("Branch", deployed.branches.ftm.branch);
  this.route = await hre.ethers.getContractAt("LzRouteBranch", deployed.branches.ftm.route);
  this.ftm = await hre.ethers.getContractAt("ERC20Mock", deployed.branches.ftm.FTM);
  let fees = await this.route.estimateFees(1);
  console.log(fees);
  let balance_matic_client = await this.ftm.balanceOf(this.branch.address);
  console.log("Before balance of matic pool", balance_matic_client.toString(), this.branch.address);
  balance_matic_client = await this.ftm.balanceOf(owner);
  console.log("Before balance of owner", balance_matic_client.toString(), owner);
  await(await this.branch.depositRequest(FTM, toTokenAmount(5), LZO, {value: fees})).wait();
  console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()
// test()




        

   