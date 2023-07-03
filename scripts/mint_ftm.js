let deployed = require("../deployed2.json");
const FTM = ethers.utils.formatBytes32String("FTM");
const LZO = ethers.utils.formatBytes32String("LZO");
const to = "0x68321A81bbF81c173c40add0d875B996480429A5";

let BN = require("bignumber.js");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

async function main() {
  this.ftm = await hre.ethers.getContractAt("ERC20Mock", deployed.branches.polygon.MATIC);
  this.branch = await hre.ethers.getContractAt("Branch", deployed.branches.polygon.branch);
  // await this.ftm.mint(to, toTokenAmount(100));
  console.log(deployed.branches.polygon.MATIC);
  // await this.ftm.approve(this.branch.address, toTokenAmount(100))
  // console.log(await this.ftm.balanceOf(to));
}

main().catch((error) => {
  console.error(error);
});
// test()
// test()




        

   