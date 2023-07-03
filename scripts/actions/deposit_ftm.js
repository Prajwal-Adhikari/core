let deployed = require("../../deployed2.json");
const FTM = ethers.utils.formatBytes32String("FTM");
const MATIC = ethers.utils.formatBytes32String("MATIC");
const LZO = ethers.utils.formatBytes32String("LZO");
const owner = "0x68321A81bbF81c173c40add0d875B996480429A5";

let BN = require("bignumber.js");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

async function main() {
  this.branch = await hre.ethers.getContractAt("Branch", deployed.branches.polygon.branch);
  this.route = await hre.ethers.getContractAt("LzRouteBranch", deployed.branches.polygon.route);
  this.ftm = await hre.ethers.getContractAt("ERC20Mock", deployed.branches.polygon.MATIC);
  let fees = await this.route.estimateFees(1,1);
  console.log(fees, this.branch.address);
  // let balance_matic_client = await this.ftm.balanceOf(this.branch.address);
  // console.log("Before balance of matic pool", balance_matic_client.toString(), this.branch.address);
  // balance_matic_client = await this.ftm.balanceOf(owner);
  // console.log("Before balance of owner", balance_matic_client.toString(), owner);
  await(await this.branch.depositRequest(MATIC, toTokenAmount(10), LZO, 0, {value: fees})).wait();
  console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()
// test()




        

   