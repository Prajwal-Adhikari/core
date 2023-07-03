
let deployed = require("../../deployed2.json");
const FTM = ethers.utils.formatBytes32String("FTM");
const LZO = ethers.utils.formatBytes32String("LZO");
const owner = "0x68321A81bbF81c173c40add0d875B996480429A5";

let BN = require("bignumber.js");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

async function main() {
  this.branch = await hre.ethers.getContractAt("Branch", deployed.branches.ftm.branch);
  this.route = await hre.ethers.getContractAt("LzRouteBranch", deployed.branches.ftm.route);

  let fees = await this.route.estimateFees(1,1);
  console.log(fees);

  await( await this.branch.repayRequest(FTM, toTokenAmount(2), LZO, 0, {value: fees})).wait();
  console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()
// test()




        

   