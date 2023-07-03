
let deployed = require("../../deployed2.json");
const FTM = ethers.utils.formatBytes32String("FTM");
const LZO = ethers.utils.formatBytes32String("LZO");
const owner = "0x68321A81bbF81c173c40add0d875B996480429A5";

let BN = require("bignumber.js");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

async function main() {
    this.pool = await hre.ethers.getContractAt("Pool", deployed.pool);
    this.route = await hre.ethers.getContractAt("LzRoutePool", deployed.route);
    let fees = await this.route.estimateFees(FTM,1);
    console.log(fees);
    await this.pool.borrow(FTM, FTM, toTokenAmount(2), ethers.utils.hexZeroPad(ethers.utils.getAddress( owner ), 32), LZO, 0, {value: fees});

}

main().catch((error) => {
  console.error(error);
});
// test()
// test()




        

   