const { assert, expect } = require("chai")
const chai = require('chai');
const chaiAlmost = require('chai-almost');

chai.use(chaiAlmost());
const { ethers, upgrades } = require("hardhat")
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");


let BN = require("bignumber.js");
const { keccak256 } = require("ethers/lib/utils");
const { BigNumber } = require("ethers");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}
// import { buildLiquidateParam } from './math.js';
// const {} = require('./math');
const { buildLiquidateParam } = require('./math.ts');


const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();

const MATIC = ethers.utils.formatBytes32String("MATIC");
const FTM = ethers.utils.formatBytes32String("FTM");
const BNB = ethers.utils.formatBytes32String("BNB");
const AVAX = ethers.utils.formatBytes32String("AVAX");
const LZO = ethers.utils.formatBytes32String("LZO");

// Contracts
let pool, core, liquidationManager, treasury, feeProvider, controller;
let clientA, clientB, clientC, adapterA, adapterB, adapterC, adapterS, routeA, routeB, routeC, routeS;
let roleManagerS, roleManagerA, roleManagerB, roleManagerC;
let matic, matic2, ftm, bnb, avax, ceUSDC, ceFTM, ceBNB, ceMATIC, debtUSDC, debtFTM, debtBNB, debtMATIC;


function getAddress(b, a) {
    return ethers.utils.solidityPack(['address', 'address'],
        [a, b]);
}
describe("Root Function Tests", function () {

    beforeEach(async function () {
        [developer, alice, bob, treasury, user3, user4] = await ethers.getSigners()

        // use this chainId
        this.chainIdServer = 1
        this.chainIdClientA = 2
        this.chainIdClientB = 3
        this.chainIdClientC = 1

        // create a LayerZero Endpoint mock for testing
        const LayerZeroEndpointMock = await ethers.getContractFactory("LZEndpointMock")
        this.lzEndpointMockServer = await LayerZeroEndpointMock.deploy(this.chainIdServer)
        this.lzEndpointMockClientA = await LayerZeroEndpointMock.deploy(this.chainIdClientA)
        this.lzEndpointMockClientB = await LayerZeroEndpointMock.deploy(this.chainIdClientB)
        this.lzEndpointMockClientC = this.lzEndpointMockServer;

        // this.lzEndpointMockServer.setEstimatedFees(toTokenAmount(0.001), 0);
        // this.lzEndpointMockClientA.setEstimatedFees(toTokenAmount(0.001), 0);
        // this.lzEndpointMockClientB.setEstimatedFees(toTokenAmount(0.001), 0);

        const RoleManagerBranch = await ethers.getContractFactory("RoleManagerBranch");
        roleManagerA = await upgrades.deployProxy(RoleManagerBranch, []);
        roleManagerB = await upgrades.deployProxy(RoleManagerBranch, []);
        roleManagerC = await upgrades.deployProxy(RoleManagerBranch, []);

        const RoleManagerPool = await ethers.getContractFactory("RoleManagerPool");
        roleManagerS = await upgrades.deployProxy(RoleManagerPool, []);

        const CEToken = await ethers.getContractFactory("CEToken");
        ceMATIC = await upgrades.deployProxy(CEToken, ["CEMATIC", "CEMATIC", roleManagerS.address]);
        ceFTM = await upgrades.deployProxy(CEToken, ["CEFTM", "CEFTM", roleManagerS.address]);
        ceBNB = await upgrades.deployProxy(CEToken, ["CEBNB", "CEBNB", roleManagerS.address]);
        ceUSDC = await upgrades.deployProxy(CEToken, ["CEUSDC", "CEUSDC", roleManagerS.address]);

        const DebtToken = await ethers.getContractFactory("DebtToken");
        debtMATIC = await upgrades.deployProxy(DebtToken, ["DebtMATIC", "DebtMATIC", roleManagerS.address]);
        debtFTM = await upgrades.deployProxy(DebtToken, ["DebtFTM", "DebtFTM", roleManagerS.address]);
        debtBNB = await upgrades.deployProxy(DebtToken, ["DebtBNB", "DebtBNB", roleManagerS.address]);
        debtUSDC = await upgrades.deployProxy(DebtToken, ["DebtUSDC", "DebtUSDC", roleManagerS.address]);

        const ERC20 = await ethers.getContractFactory("ERC20Mock")
        matic = await ERC20.deploy("MATIC", "MATIC", 18)
        ftm = await ERC20.deploy("FTM", "FTM", 18)
        bnb = await ERC20.deploy("BNB", "BNB", 18)
        avax = await ERC20.deploy("AVAX", "AVAX", 18)

        const FeeProvider = await ethers.getContractFactory("FeeProvider");
        feeProvider = await upgrades.deployProxy(FeeProvider, [roleManagerS.address]);

        const Oracle = await ethers.getContractFactory("OracleMock");
        this.oracle = await Oracle.deploy();

        const Client = await ethers.getContractFactory("Branch");
        clientA = await upgrades.deployProxy(Client, [treasury.address, roleManagerA.address]);
        clientB = await upgrades.deployProxy(Client, [treasury.address, roleManagerB.address]);
        clientC = await upgrades.deployProxy(Client, [treasury.address, roleManagerC.address]);

        // Client Adapter
        const Adapter = await ethers.getContractFactory("AdapterBranch");
        adapterA = await upgrades.deployProxy(Adapter, [roleManagerA.address]);
        adapterB = await upgrades.deployProxy(Adapter, [roleManagerB.address]);
        adapterC = await upgrades.deployProxy(Adapter, [roleManagerC.address]);

        // Client Route 400000 gas for testing
        const Route = await ethers.getContractFactory("LzRouteBranch");
        routeA = await upgrades.deployProxy(Route, [this.lzEndpointMockClientA.address, this.chainIdClientA, this.chainIdServer, 600000, roleManagerA.address]);
        routeB = await upgrades.deployProxy(Route, [this.lzEndpointMockClientB.address, this.chainIdClientB, this.chainIdServer, 600000, roleManagerB.address]);
        routeC = await upgrades.deployProxy(Route, [this.lzEndpointMockClientC.address, this.chainIdClientC, this.chainIdServer, 600000, roleManagerC.address]);

        const Server = await ethers.getContractFactory("Pool");
        pool = await upgrades.deployProxy(Server, [treasury.address, roleManagerS.address]);

        // Server Adapter
        const AdapterPool = await ethers.getContractFactory("AdapterPool");
        adapterS = await upgrades.deployProxy(AdapterPool, [roleManagerS.address]);



        const Core = await ethers.getContractFactory("Core");
        core = await upgrades.deployProxy(Core, [treasury.address, roleManagerS.address]);

        // Server Route
        const LzRoutePool = await ethers.getContractFactory("LzRoutePool");
        routeS = await upgrades.deployProxy(LzRoutePool, [this.lzEndpointMockServer.address, this.chainIdServer, 600000, roleManagerS.address]);

        const LiquidationManager = await ethers.getContractFactory("LiquidationManager");
        liquidationManager = await upgrades.deployProxy(LiquidationManager, [roleManagerS.address]);

        const Controller = await ethers.getContractFactory("Controller");
        controller = await upgrades.deployProxy(Controller, [roleManagerS.address]);

        // Grant roles to accounts in roleManager contract
        await grantRole();

        // Set roleManager contract in all other contracts
        await setRoleManager();

        // Configure Branch in Adapter
        await adapterA.setBranch(clientA.address);
        await adapterB.setBranch(clientB.address);
        await adapterC.setBranch(clientC.address);

        // Configure Adapter in Route
        await routeA.setAdapter(adapterA.address);
        await routeB.setAdapter(adapterB.address);
        await routeC.setAdapter(adapterC.address);

        // Configure Route in Adapter
        await adapterA.setRoute(LZO, routeA.address);
        await adapterB.setRoute(LZO, routeB.address);
        await adapterC.setRoute(LZO, routeC.address);

        // Configure Adapter in Client
        await clientA.setAdapter(adapterA.address);
        await clientB.setAdapter(adapterB.address);
        await clientC.setAdapter(adapterC.address);

        // Configure Pool in Adapter
        await adapterS.setPool(pool.address);

        // Configure Route in Adapter
        await adapterS.setRoute(LZO, routeS.address);

        // Configure Route methods in pool
        await routeS.setAdapter(adapterS.address);
        await routeS.setChainKeyID(MATIC, this.chainIdServer);
        await routeS.setChainKeyID(FTM, this.chainIdClientA);
        await routeS.setChainKeyID(BNB, this.chainIdClientB);

        // Configure Adapter in Pool
        await pool.setAdapter(adapterS.address);


        await ceMATIC.setCore(core.address, MATIC);
        await ceFTM.setCore(core.address, FTM);
        await ceBNB.setCore(core.address, BNB);
        await ceUSDC.setCore(core.address, AVAX);

        await debtMATIC.setCore(core.address, MATIC);
        await debtFTM.setCore(core.address, FTM);
        await debtBNB.setCore(core.address, BNB);
        await debtUSDC.setCore(core.address, AVAX);

        await core.setOracle(this.oracle.address);
        await pool.setCore(core.address);
        await pool.setFeeProvider(feeProvider.address);
        await feeProvider.setCore(core.address);
        await this.oracle.setPrice([MATIC, FTM, BNB, AVAX], [toTokenAmount(1), toTokenAmount(1), toTokenAmount(1), toTokenAmount(1)])
        await liquidationManager.setOracle(this.oracle.address);
        await liquidationManager.setCore(core.address);

        // alice account only has the permission to init pool
        await core.connect(alice).initPool(MATIC, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.1), toTokenAmount(0.15)], ceMATIC.address, debtMATIC.address);
        await core.connect(alice).initPool(FTM, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.1), toTokenAmount(0.15)], ceFTM.address, debtFTM.address);
        await core.connect(alice).initPool(BNB, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.1), toTokenAmount(0.15)], ceBNB.address, debtBNB.address);
        await core.connect(alice).initPool(AVAX, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.1), toTokenAmount(0.15)], ceUSDC.address, debtUSDC.address);


        // bob account only has the permission to change pool status
        await core.connect(bob).changePoolStatus(MATIC, true);
        await core.connect(bob).changePoolStatus(FTM, true);
        await core.connect(bob).changePoolStatus(BNB, true);
        await core.connect(bob).changePoolStatus(AVAX, true);

        await this.lzEndpointMockServer.setDestLzEndpoint(routeA.address, this.lzEndpointMockClientA.address)
        await this.lzEndpointMockServer.setDestLzEndpoint(routeB.address, this.lzEndpointMockClientB.address)

        await this.lzEndpointMockClientA.setDestLzEndpoint(routeS.address, this.lzEndpointMockServer.address)
        await this.lzEndpointMockClientB.setDestLzEndpoint(routeS.address, this.lzEndpointMockServer.address)
        // set each contracts source address so it can send to each other
        await routeA.setTrustedRemote(this.chainIdServer, getAddress(routeA.address, routeS.address))
        await routeB.setTrustedRemote(this.chainIdServer, getAddress(routeB.address, routeS.address))
        await routeC.setTrustedRemote(this.chainIdServer, getAddress(routeC.address, routeS.address))

        await routeS.setTrustedRemote(this.chainIdClientA, getAddress(routeS.address, routeA.address))
        await routeS.setTrustedRemote(this.chainIdClientB, getAddress(routeS.address, routeB.address))
        await routeS.setTrustedRemote(this.chainIdClientC, getAddress(routeS.address, routeC.address))

        await matic.mint(alice.address, toTokenAmount(100))
        await ftm.mint(alice.address, toTokenAmount(100))
        await bnb.mint(alice.address, toTokenAmount(100))
        await avax.mint(alice.address, toTokenAmount(100))

        await matic.mint(bob.address, toTokenAmount(100))
        await ftm.mint(bob.address, toTokenAmount(100))
        await bnb.mint(bob.address, toTokenAmount(100))
        await avax.mint(bob.address, toTokenAmount(100))

        await matic.mint(user3.address, toTokenAmount(100))
        await ftm.mint(user3.address, toTokenAmount(100))
        await bnb.mint(user3.address, toTokenAmount(100))
        await avax.mint(user3.address, toTokenAmount(100))

        await matic.mint(user4.address, toTokenAmount(100))
        await ftm.mint(user4.address, toTokenAmount(100))
        await bnb.mint(user4.address, toTokenAmount(100))
        await avax.mint(user4.address, toTokenAmount(100))

        await matic.connect(alice).approve(clientA.address, toTokenAmount(100));
        await matic.connect(alice).approve(clientB.address, toTokenAmount(100));
        await matic.connect(alice).approve(clientC.address, toTokenAmount(100));
        await ftm.connect(alice).approve(clientA.address, toTokenAmount(100));
        await ftm.connect(alice).approve(clientB.address, toTokenAmount(100));
        await ftm.connect(alice).approve(clientC.address, toTokenAmount(100));
        await bnb.connect(alice).approve(clientA.address, toTokenAmount(100));
        await bnb.connect(alice).approve(clientB.address, toTokenAmount(100));
        await bnb.connect(alice).approve(clientC.address, toTokenAmount(100));

        await avax.connect(alice).approve(clientA.address, toTokenAmount(100));
        await avax.connect(alice).approve(clientB.address, toTokenAmount(100));
        await avax.connect(alice).approve(clientC.address, toTokenAmount(100));

        await matic.connect(bob).approve(clientA.address, toTokenAmount(100));
        await matic.connect(bob).approve(clientB.address, toTokenAmount(100));
        await matic.connect(bob).approve(clientC.address, toTokenAmount(100));
        await ftm.connect(bob).approve(clientA.address, toTokenAmount(100));
        await ftm.connect(bob).approve(clientB.address, toTokenAmount(100));
        await ftm.connect(bob).approve(clientC.address, toTokenAmount(100));
        await bnb.connect(bob).approve(clientA.address, toTokenAmount(100));
        await bnb.connect(bob).approve(clientB.address, toTokenAmount(100));
        await bnb.connect(bob).approve(clientC.address, toTokenAmount(100));
        await avax.connect(bob).approve(clientA.address, toTokenAmount(100));
        await avax.connect(bob).approve(clientB.address, toTokenAmount(100));
        await avax.connect(bob).approve(clientC.address, toTokenAmount(100));

        await matic.connect(user3).approve(clientA.address, toTokenAmount(100));
        await matic.connect(user3).approve(clientB.address, toTokenAmount(100));
        await matic.connect(user3).approve(clientC.address, toTokenAmount(100));
        await ftm.connect(user3).approve(clientA.address, toTokenAmount(100));
        await ftm.connect(user3).approve(clientB.address, toTokenAmount(100));
        await ftm.connect(user3).approve(clientC.address, toTokenAmount(100));
        await bnb.connect(user3).approve(clientA.address, toTokenAmount(100));
        await bnb.connect(user3).approve(clientB.address, toTokenAmount(100));
        await bnb.connect(user3).approve(clientC.address, toTokenAmount(100));
        await avax.connect(user3).approve(clientA.address, toTokenAmount(100));
        await avax.connect(user3).approve(clientB.address, toTokenAmount(100));
        await avax.connect(user3).approve(clientC.address, toTokenAmount(100));

        await matic.connect(user4).approve(clientA.address, toTokenAmount(100));
        await matic.connect(user4).approve(clientB.address, toTokenAmount(100));
        await matic.connect(user4).approve(clientC.address, toTokenAmount(100));
        await ftm.connect(user4).approve(clientA.address, toTokenAmount(100));
        await ftm.connect(user4).approve(clientB.address, toTokenAmount(100));
        await ftm.connect(user4).approve(clientC.address, toTokenAmount(100));
        await bnb.connect(user4).approve(clientA.address, toTokenAmount(100));
        await bnb.connect(user4).approve(clientB.address, toTokenAmount(100));
        await bnb.connect(user4).approve(clientC.address, toTokenAmount(100));
        await avax.connect(user4).approve(clientA.address, toTokenAmount(100));
        await avax.connect(user4).approve(clientB.address, toTokenAmount(100));
        await avax.connect(user4).approve(clientC.address, toTokenAmount(100));

        await clientA.setPool(AVAX, avax.address, true);
        await clientA.setPool(MATIC, matic.address, true);
        await clientA.setPool(FTM, ftm.address, true);
        await clientA.setPool(BNB, bnb.address, true);

        await clientB.setPool(AVAX, avax.address, true);
        await clientB.setPool(MATIC, matic.address, true);
        await clientB.setPool(FTM, ftm.address, true);
        await clientB.setPool(BNB, bnb.address, true);

        await clientC.setPool(AVAX, avax.address, true);
        await clientC.setPool(MATIC, matic.address, true);
        await clientC.setPool(FTM, ftm.address, true);
        await clientC.setPool(BNB, bnb.address, true);

        // matic2 = await ERC20.deploy("MATIC", "MATIC", 21)
        // // await matic2.mint(alice.address, toTokenAmount(5e6, 21))
        // await matic2.connect(alice).approve(clientA.address, toTokenAmount(100, 21));
        // //overwrite previous initialization
        // await clientA.setPool(MATIC, matic2.address, true);

        console.log("finish")
    })
    async function grantRole() {
        // Grant roles for Branch A
        await roleManagerA.grantRole(await roleManagerA.SET_ADAPTER_METHOD(), developer.address);
        await roleManagerA.grantRole(await roleManagerA.SET_BRANCH_METHOD(), developer.address);
        await roleManagerA.grantRole(await roleManagerA.SET_ROUTE_METHOD(), developer.address);
        await roleManagerA.grantRole(await roleManagerA.SET_POOL(), developer.address);
        await roleManagerA.grantRole(await roleManagerA.PROTOCOL_PAUSE(), developer.address);
        await roleManagerA.grantRole(await roleManagerA.EMERGENCY_WITHDRAW(), developer.address);
        await roleManagerA.grantRole(await roleManagerA.SWAP(), developer.address);
        await roleManagerA.grantRole(await roleManagerA.BRANCH(), clientA.address);
        await roleManagerA.grantRole(await roleManagerA.ADAPTER(), adapterA.address);
        await roleManagerA.grantRole(await roleManagerA.ROUTE(), routeA.address);

        // Grant roles for Branch B
        await roleManagerB.grantRole(await roleManagerB.SET_ADAPTER_METHOD(), developer.address);
        await roleManagerB.grantRole(await roleManagerB.SET_BRANCH_METHOD(), developer.address);
        await roleManagerB.grantRole(await roleManagerB.SET_ROUTE_METHOD(), developer.address);
        await roleManagerB.grantRole(await roleManagerB.SET_POOL(), developer.address);
        await roleManagerB.grantRole(await roleManagerB.PROTOCOL_PAUSE(), developer.address);
        await roleManagerB.grantRole(await roleManagerB.EMERGENCY_WITHDRAW(), developer.address);
        await roleManagerB.grantRole(await roleManagerB.SWAP(), developer.address);
        await roleManagerB.grantRole(await roleManagerB.BRANCH(), clientB.address);
        await roleManagerB.grantRole(await roleManagerB.ADAPTER(), adapterB.address);
        await roleManagerB.grantRole(await roleManagerB.ROUTE(), routeB.address);

        // Grant roles for Branch C
        await roleManagerC.grantRole(await roleManagerC.SET_ADAPTER_METHOD(), developer.address);
        await roleManagerC.grantRole(await roleManagerC.SET_BRANCH_METHOD(), developer.address);
        await roleManagerC.grantRole(await roleManagerC.SET_ROUTE_METHOD(), developer.address);
        await roleManagerC.grantRole(await roleManagerC.SET_POOL(), developer.address);
        await roleManagerC.grantRole(await roleManagerC.PROTOCOL_PAUSE(), developer.address);
        await roleManagerC.grantRole(await roleManagerC.EMERGENCY_WITHDRAW(), developer.address);
        await roleManagerC.grantRole(await roleManagerC.SWAP(), developer.address);
        await roleManagerC.grantRole(await roleManagerC.BRANCH(), clientC.address);
        await roleManagerC.grantRole(await roleManagerC.ADAPTER(), adapterC.address);
        await roleManagerC.grantRole(await roleManagerC.ROUTE(), routeC.address);

        //Grant roles for Pool
        await roleManagerS.grantRole(await roleManagerS.SET_POOL_METHOD(), developer.address);
        await roleManagerS.grantRole(await roleManagerS.SET_CORE_METHOD(), developer.address);
        await roleManagerS.grantRole(await roleManagerS.SET_ADAPTER_METHOD(), developer.address);
        await roleManagerS.grantRole(await roleManagerS.SET_ROUTE_METHOD(), developer.address);
        await roleManagerS.grantRole(await roleManagerS.SET_LIQUIDATION_METHOD(), developer.address);
        await roleManagerS.grantRole(await roleManagerS.SET_FEEPROVIDER_METHOD(), developer.address);
        await roleManagerS.grantRole(await roleManagerS.SET_CE_TOKEN_METHOD(), developer.address);
        await roleManagerS.grantRole(await roleManagerS.SET_CONTROLLER_METHOD(), developer.address);
        await roleManagerS.grantRole(await roleManagerS.INIT_POOL(), alice.address);
        await roleManagerS.grantRole(await roleManagerS.POOL_STATUS(), bob.address);
        await roleManagerS.grantRole(await roleManagerS.PROTOCOL_PAUSE(), developer.address);
        await roleManagerS.grantRole(await roleManagerS.MINT_BURN_CE_DEBT_TOKEN(), liquidationManager.address);
        await roleManagerS.grantRole(await roleManagerS.MINT_BURN_CE_DEBT_TOKEN(), core.address);
        await roleManagerS.grantRole(await roleManagerS.POOL(), pool.address);
        await roleManagerS.grantRole(await roleManagerS.LIQUIDATION_MANAGER(), liquidationManager.address);
        await roleManagerS.grantRole(await roleManagerS.FEE_PROVIDER(), feeProvider.address);
        await roleManagerS.grantRole(await roleManagerS.CORE(), core.address);
        await roleManagerS.grantRole(await roleManagerS.CONTROLLER(), controller.address);
        await roleManagerS.grantRole(await roleManagerS.ADAPTER(), adapterS.address);
        await roleManagerS.grantRole(await roleManagerS.ROUTE(), routeS.address);
    }

    async function setRoleManager() {
        // Set RoleManager in Branch A
        await adapterA.setRoleManager(roleManagerA.address);
        await routeA.setRoleManager(roleManagerA.address);
        await clientA.setRoleManager(roleManagerA.address);

        // Set RoleManager in Branch B
        await adapterB.setRoleManager(roleManagerB.address);
        await routeB.setRoleManager(roleManagerB.address);
        await clientB.setRoleManager(roleManagerB.address);

        // Set RoleManager in Branch C
        await adapterC.setRoleManager(roleManagerC.address);
        await routeC.setRoleManager(roleManagerC.address);
        await clientC.setRoleManager(roleManagerC.address);

        // Set RoleManager in Pool
        await adapterS.setRoleManager(roleManagerS.address);
        await routeS.setRoleManager(roleManagerS.address);
        await pool.setRoleManager(roleManagerS.address);
        await controller.setRoleManager(roleManagerS.address);
        await core.setRoleManager(roleManagerS.address);
        await feeProvider.setRoleManager(roleManagerS.address);
        await liquidationManager.setRoleManager(roleManagerS.address);
        await ceMATIC.setRoleManager(roleManagerS.address);
        await ceBNB.setRoleManager(roleManagerS.address);
        await ceFTM.setRoleManager(roleManagerS.address);
        await debtMATIC.setRoleManager(roleManagerS.address);
        await debtBNB.setRoleManager(roleManagerS.address);
        await debtFTM.setRoleManager(roleManagerS.address);
    }

    async function printInfo() {
        console.log();
        let matic_reserve = await core.pools(MATIC);
        console.log("MATIC");
        console.log(`interest rate: ${matic_reserve[0]} currentRatio: ${matic_reserve[1]} ceScaled: ${matic_reserve[4]}`)
        console.log(`dtScaled: ${matic_reserve[5]} ceSupply: ${matic_reserve[7]} debtSupply: ${matic_reserve[8]}`)

        console.log();
        let ftm_reserve = await core.pools(FTM);
        console.log("FTM");
        console.log(`interest rate: ${ftm_reserve[0]} currentRatio: ${ftm_reserve[1]} ceScaled: ${ftm_reserve[4]}`)
        console.log(`dtScaled: ${ftm_reserve[5]} ceSupply: ${ftm_reserve[7]} debtSupply: ${ftm_reserve[8]}`)

        console.log();
        let bnb_reserve = await core.pools(BNB);
        console.log("BNB");
        console.log(`interest rate: ${bnb_reserve[0]} currentRatio: ${bnb_reserve[1]} ceScaled: ${bnb_reserve[4]}`)
        console.log(`dtScaled: ${bnb_reserve[5]} ceSupply: ${bnb_reserve[7]} debtSupply: ${bnb_reserve[8]}`)

        let balance_matic_alice = await matic.balanceOf(alice.address);
        let balance_matic_bob = await matic.balanceOf(bob.address);

        let balance_ftm_alice = await ftm.balanceOf(alice.address);
        let balance_ftm_bob = await ftm.balanceOf(bob.address);

        let balance_bnb_alice = await bnb.balanceOf(alice.address);
        let balance_bnb_bob = await bnb.balanceOf(bob.address);

        console.log();
        console.log(`alice balance matic: ${balance_matic_alice} ftm: ${balance_ftm_alice} bnb: ${balance_bnb_alice}`)
        console.log(`bob balance matic: ${balance_matic_bob} ftm: ${balance_ftm_bob} bnb: ${balance_bnb_bob}`)

        console.log();
        let factor = await core.healthFactor(alice.address);
        console.log(`alice health factor collateral:${factor[0]} debt:${factor[1]} factor:${factor[2]} lts:${factor[3]}`)
        console.log();
        factor = await core.healthFactor(bob.address);
        console.log(`bob health factor collateral:${factor[0]} debt:${factor[1]} factor:${factor[2]} lts:${factor[3]}`)
    }

    async function printCEBalance() {
        console.log("print ceToken balance")
        let alice_balance = await ceFTM.balanceOf(alice.address);
        let bob_balance = await ceFTM.balanceOf(bob.address);
        console.log(`ceToken alice: ${alice_balance} bob: ${bob_balance}`);

        console.log("print debtToken balance")
        alice_balance = await debtFTM.balanceOf(alice.address);
        bob_balance = await debtFTM.balanceOf(bob.address);
        console.log(`debtToken alice: ${alice_balance} bob: ${bob_balance}`);
    }

    async function printPoolInfo() {
        let matic_reserve = await core.pools(MATIC);
        console.log("MATIC");
        console.log(`interest rate: ${matic_reserve[0]} currentRatio: ${matic_reserve[1]} ceScaled: ${matic_reserve[4]}`)
        console.log(`dtScaled: ${matic_reserve[5]} ceSupply: ${matic_reserve[7]} debtSupply: ${matic_reserve[8]}`)
        console.log()

        let ftm_reserve = await core.pools(FTM);
        console.log("FTM");
        console.log(`interest rate: ${ftm_reserve[0]} currentRatio: ${ftm_reserve[1]} ceScaled: ${ftm_reserve[4]}`)
        console.log(`dtScaled: ${ftm_reserve[5]} ceSupply: ${ftm_reserve[7]} debtSupply: ${ftm_reserve[8]}`)
        console.log()

        let bnb_reserve = await core.pools(BNB);
        console.log("BNB");
        console.log(`interest rate: ${bnb_reserve[0]} currentRatio: ${bnb_reserve[1]} ceScaled: ${bnb_reserve[4]}`)
        console.log(`dtScaled: ${bnb_reserve[5]} ceSupply: ${bnb_reserve[7]} debtSupply: ${bnb_reserve[8]}`)
        console.log()
    }

    async function printSpecificChainLiquidity(poolId){

        let maticChainPoolliquidity = await core.chainLiquidity(MATIC,poolId);
        let bnbChainPoolliquidity = await core.chainLiquidity(BNB,poolId);
        let ftmChainPoolliquidity = await core.chainLiquidity(FTM,poolId);
        console.log();
        console.log("Matic");
        console.log(` Matic Chain liquidity = ${maticChainPoolliquidity}` );
        console.log();
        console.log("BNB");
        console.log(`BNB Chain liquidity = ${bnbChainPoolliquidity}`);
        console.log();
        console.log("FTM");
        console.log(`FTM Chain liquidity = ${ftmChainPoolliquidity}`);

    }
    async function printBlockTimestamp() {
        const blockNumber = await ethers.provider.getBlockNumber();
        const block = await ethers.provider.getBlock(blockNumber);
        console.log(`Block timestamp: ${block.timestamp}`);
      }
    
    describe("1. Testing setting of functions of Pool contract ", () => {

        it("Only authorised can configure role manager address", async () => {

            expect(await pool.roleManager()).to.equal(roleManagerS.address);
            await expect(pool.connect(alice).setRoleManager(feeProvider.address)).to.be.reverted;
            await pool.connect(developer).setRoleManager(feeProvider.address);
            expect(await pool.roleManager()).to.equal(feeProvider.address);
        });
          
        it("Only authorised can configure fee provider contract", async () => {

            expect(await pool.feeProvider()).to.equal(feeProvider.address);
            await expect(pool.connect(alice).setFeeProvider(roleManagerS.address)).to.be.reverted;
            await pool.connect(developer).setFeeProvider(roleManagerS.address);
            expect(await pool.feeProvider()).to.equal(roleManagerS.address);

            
          });
        
        it("Only authorised can configure core contract", async () => {

            expect(await pool.core()).to.equal(core.address);
            await expect(pool.connect(alice).setCore(roleManagerS.address)).to.be.reverted;
            await pool.connect(developer).setCore(roleManagerS.address);
            expect(await pool.core()).to.equal(roleManagerS.address);
        
        });
        
        it("Only authorised can configure adapter contract", async () => {

            expect(await pool.adapter()).to.equal(adapterS.address);
            await expect(pool.connect(alice).setAdapter(roleManagerS.address)).to.be.reverted;
            await pool.connect(developer).setAdapter(roleManagerS.address);
            expect(await pool.adapter()).to.equal(roleManagerS.address);

        });

        it("Only authorised can configure forwarder contract", async () => {

            expect(await pool._trustedForwarder()).to.equal(treasury.address);
            await expect(pool.connect(alice).setForwarder(roleManagerS.address)).to.be.reverted;
            await pool.connect(developer).setForwarder(roleManagerS.address);
            expect(await pool._trustedForwarder()).to.equal(roleManagerS.address);
        
        });

        it("Only authorised can configure status of the protocol on and off", async () => {

            expect(await pool.protocolPause()).to.equal(false);
            await expect(pool.connect(alice).toggleProtocolStatus()).to.be.reverted;
            await pool.connect(developer).toggleProtocolStatus();
            expect(await pool.protocolPause()).to.equal(true);

        });

        it("Only authorised can configure pool status for withdraw", async () => {

            expect(await pool.withdrawPause(MATIC,BNB)).to.equal(false);
            await expect(pool.connect(alice).setWithdrawPause(MATIC,BNB,true)).to.be.reverted;
            await pool.connect(developer).setWithdrawPause(MATIC,BNB,true);
            expect(await pool.withdrawPause(MATIC,BNB)).to.equal(true);

        });

        it("Only authorised can configure pool status for borrow", async () => {

            expect(await pool.borrowPause(MATIC,BNB)).to.equal(false);
            await expect(pool.connect(alice).setBorrowPause(MATIC,BNB,true)).to.be.reverted;
            await pool.connect(developer).setBorrowPause(MATIC,BNB,true);
            expect(await pool.borrowPause(MATIC,BNB)).to.equal(true);

        });
        
        it("Only authorised can configure Fee Enabled Status", async () => {

            expect(await pool.feeEnable()).to.equal(false);
            await expect(pool.connect(alice).toggleFeeEnable()).to.be.reverted;
            await pool.connect(developer).toggleFeeEnable();
            expect(await pool.feeEnable()).to.equal(true);

        });

        it("Only authorised can configure Reward Enabled Status", async () => {

            expect(await pool.rewardEnable()).to.equal(false);
            await expect(pool.connect(alice).toggleRewardEnable()).to.be.reverted;
            await pool.connect(developer).toggleRewardEnable();
            expect(await pool.rewardEnable()).to.equal(true);

        });
    
    });
    
    describe("2. Testing setting of functions of Core contract ", () => {

        it("Only authorised can configure role manager address", async () => {
            
            expect(await core.roleManager()).to.equal(roleManagerS.address);
            await expect(core.connect(alice).setRoleManager(feeProvider.address)).to.be.reverted;
            await core.connect(developer).setRoleManager(feeProvider.address);
            expect(await core.roleManager()).to.equal(feeProvider.address);
            
        });

        it("Only authorised can set the oracle address", async () => {

            await expect(core.connect(alice).setOracle(feeProvider.address)).to.be.reverted;
            await core.connect(developer).setOracle(feeProvider.address);
            expect(await core.oracle()).to.equal(feeProvider.address);
          
        });

        it("Only authorised can change pool status", async () => {
            
            let poolDetails = await core.pools(MATIC);
            expect(await poolDetails.enable).to.equal(true);
            await expect(core.connect(alice).changePoolStatus(MATIC,false)).to.be.reverted;
            await core.connect(bob).changePoolStatus(MATIC,false);
            let changedPoolDetails = await core.pools(MATIC);
            expect(await changedPoolDetails.enable).to.equal(false);
            
        });

    });

    describe("3. Testing the withdraw ", async () => {
        
        it("Withdrawing from differnt chain than deposited", async function () {
            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees })
            await clientC.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees })
            await clientB.connect(bob).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees })
            expect(await ceMATIC.balanceOf(alice.address)).to.equal("20000000000000000000");
            await pool.connect(alice).withdraw(MATIC, BNB, toTokenAmount(10), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, false, { value: fees })
            expect(await ceMATIC.balanceOf(alice.address)).to.equal("10000000000000000000");
        })

        it("Withdrawing reverts when deposit is not done", async function () {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees })
            await expect (pool.connect(bob).withdraw(MATIC, BNB, toTokenAmount(10), ethers.utils.hexZeroPad(bob.address, 32), LZO, 0, false, { value: fees })).to.be.revertedWithCustomError(core, "NotEnoughLiquidity").withArgs("Core",BNB,MATIC,0,10000000000000000000n);

        })

        it("Withdrawing reverts when withdrawing without any deposit", async function () {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(20), LZO, 0, { value: fees })
            await clientB.connect(alice).depositRequest(MATIC, toTokenAmount(20), LZO, 0, { value: fees })
           await clientC.connect(alice).depositRequest(MATIC, toTokenAmount(30), LZO, 0, { value: fees })
            expect(await ceMATIC.balanceOf(alice.address)).to.equal("70000000000000000000");
            await expect (pool.connect(bob).withdraw(MATIC, MATIC, toTokenAmount(20), ethers.utils.hexZeroPad(bob.address, 32), LZO, 0, false, { value: fees })).to.be.revertedWithCustomError(ceMATIC, "NotEnoughCeTokens").withArgs("CEToken",bob.address);

        })

        it("Withdraw reverts when there is no any liquidity in a chain's pool", async function () {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(20), LZO, 0, { value: fees })
            await clientB.connect(bob).depositRequest(MATIC, toTokenAmount(20), LZO, 0, { value: fees })
            expect(await ceMATIC.balanceOf(alice.address)).to.equal("20000000000000000000");
            expect(await ceMATIC.balanceOf(bob.address)).to.equal("20000000000000000000");
            await pool.connect(alice).withdraw(MATIC, BNB, toTokenAmount(20), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, false, { value: fees });
            await expect (pool.connect(bob).withdraw(MATIC, BNB, toTokenAmount(20), ethers.utils.hexZeroPad(bob.address, 32), LZO, 0, false, { value: fees })).to.be.revertedWithCustomError(core, "NotEnoughLiquidity").withArgs("Core",BNB,MATIC,0,20000000000000000000n);
        
           
        })

        it("Withdrawing certain amount after earning certain interest", async function () {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(35), LZO, 0, { value: fees });
            await clientC.connect(bob).depositRequest(MATIC, toTokenAmount(40), LZO, 0, { value: fees });
            await clientA.connect(user3).depositRequest(FTM, toTokenAmount(10), LZO, 0, { value: fees });
            await pool.connect(user3).borrow(MATIC, FTM, toTokenAmount(5), ethers.utils.hexZeroPad(user3.address, 32), LZO, 0, { value: fees });
            await network.provider.send("evm_increaseTime", [6 * 24 * 60 * 60]);
            await network.provider.send("evm_mine");
            await pool.connect(alice).withdraw(MATIC, MATIC, 20, ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, false, { value: fees });
            let alicefactor = await core.healthFactor(alice.address);
            expect(alicefactor[0]).to.almost.equal(35000460274860476880n);
           
        })

        it("Withdrawing all after earning certain interest", async function () {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(30), LZO, 0, { value: fees });
            await clientC.connect(bob).depositRequest(MATIC, toTokenAmount(40), LZO, 0, { value: fees });
            await clientA.connect(user3).depositRequest(FTM, toTokenAmount(10), LZO, 0, { value: fees });
            await pool.connect(user3).borrow(MATIC, MATIC, toTokenAmount(5), ethers.utils.hexZeroPad(user3.address, 32), LZO, 0, { value: fees });
            await network.provider.send("evm_increaseTime", [7 * 24 * 60 * 60]);
            await network.provider.send("evm_mine");
            await pool.connect(alice).withdraw(MATIC, MATIC, 20, ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, true, { value: fees });
            let alicefactor = await core.healthFactor(alice.address);
            expect(alicefactor[0]).to.equal(0);
           
        })

    }); 

    describe("4. Testing the borrow ", async () => {

        it("Testing the borrowed amount", async function () {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(20), LZO, 0, { value: fees });
            await clientB.connect(bob).depositRequest(MATIC, toTokenAmount(20), LZO, 0, { value: fees });
           let bnbs = await bnb.balanceOf(user3.address);
            await clientC.connect(user3).depositRequest(BNB, toTokenAmount(20), LZO, 0, { value: fees });
            await pool.connect(user3).borrow(MATIC, BNB, toTokenAmount(10), ethers.utils.hexZeroPad(user3.address, 32), LZO, 0, { value: fees });
            expect(await matic.balanceOf(user3.address)).to.equal("110000000000000000000"); 

        })

        it("Collateral Health Factor of two positions should be equal when deposits are done before borrow", async function () {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees });
            await clientC.connect(bob).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees });
            await clientA.connect(user3).depositRequest(FTM, toTokenAmount(10), LZO, 0, { value: fees });
            await pool.connect(user3).borrow(MATIC, FTM, toTokenAmount(5), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees });
            await network.provider.send("evm_increaseTime", [4* 7 * 24 * 60 * 60]);
            await network.provider.send("evm_mine");
            let alicefactor = await core.healthFactor(alice.address);
            let bobfactor = await core.healthFactor(bob.address);
            expect(alicefactor[0]).to.equal(bobfactor[0]);
           
        })

        it("Testing the difference in the interest  earned when deposited in different time", async function () {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees });
            await clientB.connect(user3).depositRequest(FTM, toTokenAmount(10), LZO, 0, { value: fees });
            await pool.connect(user3).borrow(MATIC, FTM, toTokenAmount(5), ethers.utils.hexZeroPad(user3.address, 32), LZO, 0, { value: fees });
            await clientC.connect(bob).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees });
            await network.provider.send("evm_increaseTime", [7 * 24 * 60 * 60]);
            await network.provider.send("evm_mine");
            let alicefactor = await core.healthFactor(alice.address);
            let bobfactor = await core.healthFactor(bob.address);
            expect(alicefactor[0]).to.be.greaterThan(bobfactor[0]);

        })

        it("Testing the interest earned are same", async function () {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees });
            await clientA.connect(bob).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees });
            await clientB.connect(user3).depositRequest(FTM, toTokenAmount(10), LZO, 0, { value: fees });
            await pool.connect(user3).borrow(MATIC, FTM, toTokenAmount(5), ethers.utils.hexZeroPad(user3.address, 32), LZO, 0, { value: fees });
            await network.provider.send("evm_increaseTime", [60 *  60]);
            await network.provider.send("evm_mine");
            let alicefactor_one = await core.healthFactor(alice.address);
            await network.provider.send("evm_increaseTime", [60 * 60]);
            await network.provider.send("evm_mine");
            let alicefactor_Two = await core.healthFactor(alice.address);
            expect(alicefactor_one[0]).to.be.lessThan(alicefactor_Two[0]);
            
           
        })

        it("Testing the interest earned after one day", async function () {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees });
            await clientA.connect(bob).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees });
            await clientB.connect(user3).depositRequest(FTM, toTokenAmount(10), LZO, 0, { value: fees });
            await pool.connect(user3).borrow(MATIC, FTM, toTokenAmount(5), ethers.utils.hexZeroPad(user3.address, 32), LZO, 0, { value: fees });
            await network.provider.send("evm_increaseTime", [1* 24 * 60 * 60]);
            await network.provider.send("evm_mine");
            await printInfo()
            let alicefactor = await core.healthFactor(alice.address);
            expect(alicefactor[0]).to.equal(10000308219178082180n);
            
           
        })

        it("Testing the interest earned after a week", async function () {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees });
            await clientA.connect(bob).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees });
            await clientB.connect(user3).depositRequest(FTM, toTokenAmount(10), LZO, 0, { value: fees });
            await pool.connect(user3).borrow(MATIC, FTM, toTokenAmount(5), ethers.utils.hexZeroPad(user3.address, 32), LZO, 0, { value: fees });
            await network.provider.send("evm_increaseTime", [7* 24 * 60 * 60]);
            await network.provider.send("evm_mine");
            let alicefactor = await core.healthFactor(alice.address);
            expect(alicefactor[0]).to.equal(10002157534246575340n);
    
        })

        it("Testing the interest earned for the first deposit and borrow scenario ", async function () {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(1), LZO, 0, { value: fees });
            await clientA.connect(bob).depositRequest(FTM, toTokenAmount(10), LZO, 0, { value: fees });
            await pool.connect(bob).borrow(MATIC, FTM, toTokenAmount(1), ethers.utils.hexZeroPad(bob.address, 32), LZO, 0, { value: fees });
            await network.provider.send("evm_increaseTime", [7 * 24 * 60 * 60]);
            await network.provider.send("evm_mine");
            let alicefactor = await core.healthFactor(alice.address);
            let bobfactor = await core.healthFactor(bob.address);
            expect(alicefactor[0]).to.be.lessThan(bobfactor[1]);

        })

    }); 

    describe("5. Testing settings of DebtToken contract", () => {
        it("Should configure core address", async () => {
            expect(await debtMATIC.core()).to.equal(core.address);
            await expect(debtMATIC.connect(alice).setCore(core.address, MATIC)).to.be.reverted;
            await debtMATIC.connect(developer).setCore(core.address, MATIC);
            expect(await debtMATIC.core()).to.equal(core.address);
            expect(await debtMATIC.poolId()).to.equal(MATIC);

        })

        it("Only authorised can configure role manager address", async () => {
            expect(await debtFTM.roleManager()).to.equal(roleManagerS.address);
            await expect(debtFTM.connect(alice).setRoleManager(feeProvider.address)).to.be.reverted;
            await debtFTM.connect(developer).setRoleManager(feeProvider.address);
            expect(await debtFTM.roleManager()).to.equal(feeProvider.address);
        });
    })

    describe("6. Testing setting of functions of Liquidation Manager contract", () => {

        it("Only authorised can configure role manager address", async () => {
            expect(await liquidationManager.roleManager()).to.equal(roleManagerS.address);
            await expect(liquidationManager.connect(alice).setRoleManager(feeProvider.address)).to.be.reverted;
            await liquidationManager.connect(developer).setRoleManager(feeProvider.address);
            expect(await liquidationManager.roleManager()).to.equal(feeProvider.address);
        });

        it("Only authorised can configure core contract", async () => {

            expect(await liquidationManager.core()).to.equal(core.address);
            await expect(liquidationManager.connect(alice).setCore(roleManagerS.address)).to.be.reverted;
            await liquidationManager.connect(developer).setCore(roleManagerS.address);
            expect(await liquidationManager.core()).to.equal(roleManagerS.address);

        });

        it("Only authorised can set the oracle address", async () => {

            await expect(liquidationManager.connect(alice).setOracle(feeProvider.address)).to.be.reverted;
            await liquidationManager.connect(developer).setOracle(feeProvider.address);
            expect(await liquidationManager.oracle()).to.equal(feeProvider.address);

        });

        it("Only authorised can set the status for liquidation pause", async () => {
            const liquidationPause = true;
            expect(await liquidationManager.liquidationPause()).to.equal(false);
            await expect(liquidationManager.connect(alice).setLiquidationPause(liquidationPause)).to.be.reverted;
            await liquidationManager.connect(developer).setLiquidationPause(liquidationPause);
            expect(await liquidationManager.liquidationPause()).to.equal(liquidationPause);
        })

    })

    describe("7.Testing settings of FeeProvider contract", () => {

        it("Only authorised can configure role manager address", async () => {
            expect(await feeProvider.roleManager()).to.equal(roleManagerS.address);
            await expect(feeProvider.connect(alice).setRoleManager(feeProvider.address)).to.be.reverted;
            await feeProvider.connect(developer).setRoleManager(feeProvider.address);
            expect(await feeProvider.roleManager()).to.equal(feeProvider.address);
        });

        it("Only authorised can configure core contract", async () => {
            expect(await feeProvider.core()).to.equal(core.address);
            await expect(feeProvider.connect(alice).setCore(core.address)).to.be.reverted;
            await feeProvider.connect(developer).setCore(core.address);
            expect(await feeProvider.core()).to.equal(core.address);
        });
    })

    describe("8. Testing settings of CEToken contract", () => {

        it("Only authorised can configure role manager address", async () => {
            expect(await ceMATIC.roleManager()).to.equal(roleManagerS.address);
            await expect(ceMATIC.connect(alice).setRoleManager(feeProvider.address)).to.be.reverted;
            await ceMATIC.connect(developer).setRoleManager(feeProvider.address);
            expect(await ceMATIC.roleManager()).to.equal(feeProvider.address);
        });

        it("Only authorised can configure core contract", async () => {
            expect(await ceFTM.core()).to.equal(core.address);
            await expect(ceFTM.connect(alice).setCore(core.address, FTM)).to.be.reverted;
            await ceFTM.connect(developer).setCore(core.address, FTM);
            expect(await ceFTM.core()).to.equal(core.address);
            expect(await ceFTM.poolId()).to.equal(FTM);
        });

        it("Should configure amount when exceeded triggers the lock up", async () => {
            await ceUSDC.setLockupTriggerAmount(toTokenAmount(1000));
            expect(await ceUSDC.lockupTriggerAmt()).to.be.equal(toTokenAmount(1000));
        })

        it("Should configure a waiting period before transfer if the mint amount exceeds lockup trigger amount", async () => {
            await ceMATIC.setTransferBlockWait(10);
            expect(await ceMATIC.transferBlockWait()).to.equal(10);
        })

        it("Should revert if the chain is already marked as dead", async () => {

            //Initially MATIC is not in dead chain list
            expect(await ceMATIC.isChainDead(MATIC)).to.equal(false);
            //Add the chain as dead
            await ceMATIC.connect(developer).addDeadChain(MATIC);

            //Attempt to add the same chain again
            await expect(ceMATIC.connect(developer).addDeadChain(MATIC)).to.be.revertedWithCustomError(ceMATIC, "DeadChain").withArgs("CEToken", MATIC);

            //MATIC should be a dead chain now
            expect(await ceMATIC.isChainDead(MATIC)).to.equal(true);

        })

        it("Should remove chain from dead chain list", async () => {
            //Initially MATIC is not in dead chain list
            expect(await ceMATIC.isChainDead(MATIC)).to.equal(false);
            //Add the chain as dead
            await ceMATIC.connect(developer).addDeadChain(MATIC);
            //MATIC should be a dead chain now
            expect(await ceMATIC.isChainDead(MATIC)).to.equal(true);
            //now remoce MATIC from dead chain list
            await ceMATIC.connect(developer).removeDeadChain(MATIC);
            //MATIC should be a removed from dead chain lsit 
            expect(await ceMATIC.isChainDead(MATIC)).to.equal(false);
        })

        it("Should retrive all the chains that the user has its ceToken on", async () => {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees })
            await clientA.connect(alice).depositRequest(BNB, toTokenAmount(10), LZO, 0, { value: fees })
            await clientA.connect(alice).depositRequest(FTM, toTokenAmount(10), LZO, 0, { value: fees })
            expect((await ceMATIC.connect(alice).getChains(alice.address)).length).to.equal(1);
            expect((await ceBNB.connect(alice).getChains(alice.address)).length).to.equal(1);
            expect((await ceFTM.connect(alice).getChains(alice.address)).length).to.equal(1);

        })
    })

    describe("9. Testing settings of Controller smart contract", () => {

        it("Only authorised can configure role manager address", async () => {
            expect(await controller.roleManager()).to.equal(roleManagerS.address);
            await expect(controller.connect(alice).setRoleManager(feeProvider.address)).to.be.reverted;
            await controller.connect(developer).setRoleManager(feeProvider.address);
            expect(await controller.roleManager()).to.equal(feeProvider.address);
        });

    })

    describe("10. Testing setting of functions of Adapter contract", () => {

        it("Should set the roleManager address", async () => {
            await adapterS.setRoleManager(roleManagerS.address);
            const updatedRoleManagerAddress = await adapterS.roleManager();
            assert.equal(updatedRoleManagerAddress, roleManagerS.address);
        })

        it("Should configure the pool contract", async () => {
            await adapterS.setPool(pool.address);
            const updatedPoolContract = await adapterS.pool();
            assert.equal(updatedPoolContract, pool.address);
        })

        it("Should configure route address for corresponding route", async () => {
            await adapterS.setRoute(LZO, routeS.address);
            const updatedRouteAddress = await adapterS.router(LZO);
            expect(updatedRouteAddress).to.equal(routeS.address);
            expect(await adapterS.routeExist(routeS.address)).to.equal(true);
        })

    })

    
})