let deployed = require("../../deployed2.json");
const { ethers } = require("hardhat");
const MATIC = ethers.utils.formatBytes32String("MATIC");
const LZO = ethers.utils.formatBytes32String("LZO");
const AXL = ethers.utils.formatBytes32String("AXL");

const owner = "0x68321A81bbF81c173c40add0d875B996480429A5";

let BN = require("bignumber.js");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

async function buildRemoteAmount(amount, token){
  tokenContract = await hre.ethers.getContractAt("ERC20Mock", token);
  tokenDecimals = await tokenContract.decimals();
  BASE = 10**18
  
  let _localAmount;
  if (tokenDecimals > 18) {
    _localAmount = amount / (10 ** (tokenDecimals - 18));
  } else {
    _localAmount = amount * (10 ** (18 - tokenDecimals));
  }

  let amountpx = (_localAmount / BASE);
  let amountsx = (_localAmount % BASE);

  return {amountpx, amountsx};
}

async function getPayload(amountpx, amountsx, functionType, id){
  
  let payload = ethers.utils.solidityPack([
    "uint8",
    "bytes32",
    "bytes32",
    "uint64",
    "uint64"
  ],
  [
    functionType,
    MATIC,
    ethers.utils.hexZeroPad(ethers.utils.getAddress( owner ), 32),
    amountpx,
    amountsx
  ]);
  return payload;
}
async function main() {
  this.pool = await hre.ethers.getContractAt("Pool", deployed.pool);
  this.core = await hre.ethers.getContractAt("Core", deployed.core);
  this.route = await hre.ethers.getContractAt("LzRoutePool", deployed.route);
  let fees = await this.route.estimateFees(MATIC, 0); 
  console.log(fees);

  await this.pool.withdraw(MATIC, MATIC, toTokenAmount(2), ethers.utils.hexZeroPad(ethers.utils.getAddress( owner ), 32),LZO,0,0, {value: fees}); 
  console.log(ethers.utils.hexZeroPad(ethers.utils.getAddress( owner )));

  console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()
// test()




        

   