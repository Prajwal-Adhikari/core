
let deployed = require("../../deployed2.json");
const FTM = ethers.utils.formatBytes32String("FTM");
const LZO = ethers.utils.formatBytes32String("LZO");
const owner = "0x5BA85D71ef9aE0EdC180a6bf5e65F0a749f062DC";

let BN = require("bignumber.js");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

async function main() {
    this.server = await hre.ethers.getContractAt("Pool", deployed.server);
    this.route = await hre.ethers.getContractAt("LzRoutePool", deployed.route);
    let fees = await this.route.estimateFees(FTM);
    console.log(fees);
    
    await this.server.borrow(FTM, FTM, toTokenAmount(1), ethers.utils.hexZeroPad(ethers.utils.getAddress( owner ), 32), LZO, {value: fees});

}

main().catch((error) => {
  console.error(error);
});
// test()
// test()




        

   