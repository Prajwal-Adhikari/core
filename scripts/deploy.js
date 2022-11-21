// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const epServer = "0xf69186dfBa60DdB133E91E9A4B5673624293d8F8";
const epClientA = "0x93f54D755A063cE7bB9e6Ac47Eccc8e33411d706"
const epClientB = "0x7dcAD72640F835B0FA36EFD3D6d3ec902C7E5acf"
const treasury = "0x2D83750BDB3139eed1F76952dB472A512685E3e0"
const owner = "0x892a2b7cF919760e148A0d33C1eb0f44D3b383f8";

let BN = require("bignumber.js");
let provider;
let wallet
let fs = require("fs")


const OracleFile = require("../artifacts/contracts/server/Oracle.sol/Oracle.json");
const ClientFile = require("../artifacts/contracts/client/Client.sol/Client.json");
const ServerFile = require("../artifacts/contracts/server/Pool.sol/Pool.json");
const CeFile = require("../artifacts/contracts/server/CEToken.sol/CEToken.json");
const DebtFile = require("../artifacts/contracts/server/DebtToken.sol/DebtToken.json");
const ERC20File = require("../artifacts/contracts/layerZero/mocks/ERC20Mock.sol/ERC20Mock.json");

let ethers = require("ethers")

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

let deployed = require("../deployed.json");

function getId(name) {
  return ethers.utils.formatBytes32String(name)
}

const chainIdServer = 10109
const chainIdClientA = 10106
const chainIdClientB = 10112


const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();
const networks = {
  "avax": {
    "name": "avax",
    "chainId": 43113,
    "ensAddress": "https://avalanchetestapi.terminet.io/ext/bc/C/rpc"
  },
  "polygon": {
    "name": "polygon",
    "chainId": 80001,
    "ensAddress": "https://matic-mumbai.chainstacklabs.com"
  },
  "fantom": {
    "name": "fantom",
    "chainId": 4002,
    "ensAddress": "https://xapi.testnet.fantom.network/lachesis/"
  },
}

function changeNetwork(name) {
  provider = new ethers.providers.JsonRpcProvider(networks[name].ensAddress, networks[name]);
  wallet = new ethers.Wallet(`0x${process.env.PRIVATE_KEY}`, provider);
  const { EthersProviderWrapper } = require("@nomiclabs/hardhat-ethers/internal/ethers-provider-wrapper");
  hre.ethers.provider = provider;
};

async function main() {
  changeNetwork("polygon")
  let Oracle = new ethers.ContractFactory(OracleFile.abi, OracleFile.bytecode, wallet);
  let Server = new ethers.ContractFactory(ServerFile.abi, ServerFile.bytecode, wallet);

  console.log("deploy polygon")
  this.oracle = await Oracle.deploy();
  this.server = await Server.deploy(epServer, treasury)
  await this.server.setOracle(this.oracle.address)
  await deployToken("AVAX");
  await deployToken("FTM");
  await deployToken("USDC");

  console.log("deploy fantom")
  changeNetwork("fantom")
  let Client = new ethers.ContractFactory(ClientFile.abi, ClientFile.bytecode, wallet);
  this.clientB = await Client.deploy(epClientB, chainIdServer)

  console.log("deploy avax")
  changeNetwork("avax")
  Client = new ethers.ContractFactory(ClientFile.abi, ClientFile.bytecode, wallet);
  this.clientA = await Client.deploy(epClientA, chainIdServer)  

  // console.log(this.oracle.address, this.server.address);
  deployed.server = this.server.address
  deployed.clientA = this.clientA.address;
  deployed.clientB = this.clientB.address;
  deployed.oracle = this.oracle.address;
  fs.writeFileSync("./deployed.json", JSON.stringify(deployed, null, 4))
  await config()
}

function getAddress(b, a) {
  return ethers.utils.solidityPack(['address','address'],
                    [a, b]);
}

async function deployToken(name) {
  console.log(`deploy token`);
  let CEToken = new ethers.ContractFactory(CeFile.abi, CeFile.bytecode, wallet);
  let ceToken = await CEToken.deploy("ce" + name, "ce" + name);
  let DebtToken = new ethers.ContractFactory(DebtFile.abi, DebtFile.bytecode, wallet);
  let debtToken = await DebtToken.deploy("debt" + name, "debt" + name);
  await server.initPool(getId(name), [toTokenAmount(0.5), toTokenAmount(0.1),
   toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.8), toTokenAmount(0.1), toTokenAmount(0.05)],
    ceToken.address, debtToken.address);
  await ceToken.initialize(this.server.address);
  await debtToken.initialize(this.server.address);
  await this.server.changePoolStatus(getId(name), true);
}

async function config() {
  console.log("config server")
  changeNetwork("polygon");
  this.oracle = new ethers.Contract(deployed.oracle, OracleFile.abi, provider);
  this.server = new ethers.Contract(deployed.server, ServerFile.abi, provider); 
  await (await this.oracle.connect(wallet).setPrice([getId("USDC"), getId("FTM"), getId("AVAX")], [toTokenAmount(1), toTokenAmount(1), toTokenAmount(1)])).wait()

  console.log("remote");
  await (await this.server.connect(wallet).setTrustedRemote(chainIdClientA, getAddress(deployed.server, deployed.clientA))).wait()
  await (await this.server.connect(wallet).setTrustedRemote(chainIdClientB, getAddress(deployed.server, deployed.clientB))).wait()

  console.log("config clientA")
  changeNetwork("avax");
  this.clientA = new ethers.Contract(deployed.clientA, ClientFile.abi, provider); 
  await (await this.clientA.connect(wallet).setTrustedRemote(chainIdServer, getAddress(deployed.clientA, deployed.server))).wait()
  await (await this.clientA.connect(wallet).setPool(getId("AVAX"), deployed.avax.AVAX, true)).wait()
  await (await this.clientA.connect(wallet).setPool(getId("USDC"), deployed.avax.USDC, true)).wait()
  this.avax = new ethers.Contract(deployed.avax.AVAX, ERC20File.abi, provider);
  await (await this.avax.connect(wallet).mint(owner, toTokenAmount(1000000))).wait();
  await (await this.avax.connect(wallet).approve(deployed.clientA, toTokenAmount(1000000))).wait();
  console.log(getId("FTM"), getId("USDC"));
  changeNetwork("fantom")
  console.log("config clientB")
  this.clientB = new ethers.Contract(deployed.clientB, ClientFile.abi, provider); 
  await (await this.clientB.connect(wallet).setTrustedRemote(chainIdServer, getAddress(deployed.clientB, deployed.server))).wait()
  await (await this.clientB.connect(wallet).setPool(getId("FTM"), deployed.ftm.FTM, true)).wait()
  await (await this.clientB.connect(wallet).setPool(getId("USDC"), deployed.ftm.USDC, true)).wait()
  this.ftm = new ethers.Contract(deployed.ftm.FTM, ERC20File.abi, provider);
  await (await this.ftm.connect(wallet).mint(owner, toTokenAmount(1000000))).wait();
  await (await this.ftm.connect(wallet).approve(deployed.clientB, toTokenAmount(1000000))).wait();

  console.log("complete");
  await test()
}

async function test() {
  console.log("simple test on production");
  changeNetwork("avax");
  this.clientA = new ethers.Contract(deployed.clientA, ClientFile.abi, provider);
  console.log("deposit")
  await (await this.clientA.connect(wallet).depositRequest(getId("AVAX"), toTokenAmount(1000), {value: ethers.utils.parseEther("10")})).wait()
  
  changeNetwork("polygon");
  this.server = new ethers.Contract(deployed.server, ServerFile.abi, provider);
  console.log("withdraw")
  await (await this.server.connect(wallet).withdraw(getId("AVAX"), chainIdClientA, toTokenAmount(500), {value: ethers.utils.parseEther("10")})).wait()
}

// console.log(getAddress(deployed.server, deployed.clientA))
// console.log(getAddress(deployed.server, deployed.clientB))
// console.log(getAddress(deployed.clientA, deployed.server))
// console.log(getAddress(deployed.clientB, deployed.server))

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
});
// test()
