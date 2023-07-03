let deployed = require("../../deployed2.json");
const { ethers } = require("hardhat");
const FTM = ethers.utils.formatBytes32String("FTM");
const LZO = ethers.utils.formatBytes32String("LZO");
const MATIC = ethers.utils.formatBytes32String("MATIC");

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
  this.matic = await hre.ethers.getContractAt("ERC20Mock", deployed.branches.polygon.MATIC);
  let fees = await this.route.estimateFees(MATIC, 0);
  console.log(fees);

  // let pool = await this.core.pools(MATIC);
  // let ceToken = pool.ceToken;
  // this.ceTokenn = await hre.ethers.getContractAt("ERC20Mock", ceToken);
  // console.log(await this.ceTokenn.balanceOf(owner));

  
  // console.log(await this.route.chainID(MATIC)) //10109
  // console.log(await this.route.payloadStatus(10109, "0x5910b2d07331585cd0b535591cdc777d2c4f0ad6c7ecfc6aca2eef8fbb1a4d57548df31148f376c9")) //true
 
  // await this.pool.withdraw(MATIC, MATIC, toTokenAmount(5), ethers.utils.hexZeroPad(ethers.utils.getAddress( owner ), 32),LZO,0, false, {value: fees});

  // trustedRemote is the remote + local format
  let remoteContract = "0x5910b2d07331585cd0b535591cdc777d2c4f0ad6"
  let localContract = "0xc7ecfc6aca2eef8fbb1a4d57548df31148f376c9"
  let trustedRemote = hre.ethers.utils.solidityPack(
      ['address','address'],
      [remoteContract, localContract]
  )
  console.log(trustedRemote);
  let payload = "0x014D4154494300000000000000000000000000000000000000000000000000000000000000000000000000000068321A81BBF81C173C40ADD0D875B996480429A5000000000000000A0000000000000000"
  await this.route.retry(10109, trustedRemote, payload);

  console.log("complete");
}

main().catch((error) => {
  console.error(error);
});
// test()
// test()




        

   