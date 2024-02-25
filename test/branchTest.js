const { assert, expect } = require("chai")
const { ethers, upgrades } = require("hardhat")

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
const USDC = ethers.utils.formatBytes32String("USDC");
const LZO = ethers.utils.formatBytes32String("LZO");

// Contracts
let pool, core, liquidationManager, treasury, feeProvider, controller;
let clientA, clientB, clientC, adapterA, adapterB, adapterC, adapterS, routeA, routeB, routeC, routeS;
let roleManagerS, roleManagerA, roleManagerB, roleManagerC;
let matic, matic2, ftm, bnb, usdc, ceUSDC, ceFTM, ceBNB, ceMATIC, debtUSDC, debtFTM, debtBNB, debtMATIC;


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
        usdc = await ERC20.deploy("USDC", "USDC", 6)

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
        routeA = await upgrades.deployProxy(Route, [this.lzEndpointMockClientA.address, this.chainIdClientA, this.chainIdServer, 800000, roleManagerA.address]);
        routeB = await upgrades.deployProxy(Route, [this.lzEndpointMockClientB.address, this.chainIdClientB, this.chainIdServer, 800000, roleManagerB.address]);
        routeC = await upgrades.deployProxy(Route, [this.lzEndpointMockClientC.address, this.chainIdClientC, this.chainIdServer, 800000, roleManagerC.address]);

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

        // Set liquidity cap ammount 
        await clientA.setCapAmount([MATIC,FTM,BNB],[toTokenAmount(9000000000),toTokenAmount(9000000000),toTokenAmount(9000000000)]);
        await clientB.setCapAmount([MATIC,FTM,BNB],[toTokenAmount(9000000000),toTokenAmount(9000000000),toTokenAmount(9000000000)]);
        await clientC.setCapAmount([MATIC,FTM,BNB],[toTokenAmount(9000000000),toTokenAmount(9000000000),toTokenAmount(9000000000)]);

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
        await ceUSDC.setCore(core.address, USDC);

        await debtMATIC.setCore(core.address, MATIC);
        await debtFTM.setCore(core.address, FTM);
        await debtBNB.setCore(core.address, BNB);
        await debtUSDC.setCore(core.address, USDC);

        await core.setOracle(this.oracle.address);
        await pool.setCore(core.address);
        await pool.setFeeProvider(feeProvider.address);
        await feeProvider.setCore(core.address);
        await this.oracle.setPrice([MATIC, FTM, BNB, USDC], [toTokenAmount(1), toTokenAmount(1), toTokenAmount(1), toTokenAmount(1)])
        await liquidationManager.setOracle(this.oracle.address);
        await liquidationManager.setCore(core.address);
         await liquidationManager.setChainId([MATIC,FTM,BNB],[MATIC,FTM,BNB]);

        // alice account only has the permission to init pool
        await core.connect(alice).initPool(MATIC, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.8), toTokenAmount(0.1), toTokenAmount(0.1), toTokenAmount(0.15)], ceMATIC.address, debtMATIC.address);
        await core.connect(alice).initPool(FTM, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.8), toTokenAmount(0.1), toTokenAmount(0.1), toTokenAmount(0.15)], ceFTM.address, debtFTM.address);
        await core.connect(alice).initPool(BNB, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.8), toTokenAmount(0.1), toTokenAmount(0.1), toTokenAmount(0.15)], ceBNB.address, debtBNB.address);
        await core.connect(alice).initPool(USDC, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.8), toTokenAmount(0.1), toTokenAmount(0.1), toTokenAmount(0.15)], ceUSDC.address, debtUSDC.address);


        // bob account only has the permission to change pool status
        await core.connect(bob).changePoolStatus(MATIC, true);
        await core.connect(bob).changePoolStatus(FTM, true);
        await core.connect(bob).changePoolStatus(BNB, true);
        await core.connect(bob).changePoolStatus(USDC, true);

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
        await usdc.mint(alice.address, toTokenAmount(100, 6))

        await matic.mint(bob.address, toTokenAmount(100))
        await ftm.mint(bob.address, toTokenAmount(100))
        await bnb.mint(bob.address, toTokenAmount(100))
        await usdc.mint(bob.address, toTokenAmount(100, 6))

        await matic.mint(user3.address, toTokenAmount(100))
        await ftm.mint(user3.address, toTokenAmount(100))
        await bnb.mint(user3.address, toTokenAmount(100))
        await usdc.mint(user3.address, toTokenAmount(100, 6))

        await matic.mint(user4.address, toTokenAmount(100))
        await ftm.mint(user4.address, toTokenAmount(100))
        await bnb.mint(user4.address, toTokenAmount(100))
        await usdc.mint(user4.address, toTokenAmount(100, 6))

        await matic.connect(alice).approve(clientA.address, toTokenAmount(100));
        await matic.connect(alice).approve(clientB.address, toTokenAmount(100));
        await matic.connect(alice).approve(clientC.address, toTokenAmount(100));
        await ftm.connect(alice).approve(clientA.address, toTokenAmount(100));
        await ftm.connect(alice).approve(clientB.address, toTokenAmount(100));
        await ftm.connect(alice).approve(clientC.address, toTokenAmount(100));
        await bnb.connect(alice).approve(clientA.address, toTokenAmount(100));
        await bnb.connect(alice).approve(clientB.address, toTokenAmount(100));
        await bnb.connect(alice).approve(clientC.address, toTokenAmount(100));

        await usdc.connect(alice).approve(clientA.address, toTokenAmount(100));
        await usdc.connect(alice).approve(clientB.address, toTokenAmount(100));
        await usdc.connect(alice).approve(clientC.address, toTokenAmount(100));

        await matic.connect(bob).approve(clientA.address, toTokenAmount(100));
        await matic.connect(bob).approve(clientB.address, toTokenAmount(100));
        await matic.connect(bob).approve(clientC.address, toTokenAmount(100));
        await ftm.connect(bob).approve(clientA.address, toTokenAmount(100));
        await ftm.connect(bob).approve(clientB.address, toTokenAmount(100));
        await ftm.connect(bob).approve(clientC.address, toTokenAmount(100));
        await bnb.connect(bob).approve(clientA.address, toTokenAmount(100));
        await bnb.connect(bob).approve(clientB.address, toTokenAmount(100));
        await bnb.connect(bob).approve(clientC.address, toTokenAmount(100));
        await usdc.connect(bob).approve(clientA.address, toTokenAmount(100));
        await usdc.connect(bob).approve(clientB.address, toTokenAmount(100));
        await usdc.connect(bob).approve(clientC.address, toTokenAmount(100));

        await matic.connect(user3).approve(clientA.address, toTokenAmount(100));
        await matic.connect(user3).approve(clientB.address, toTokenAmount(100));
        await matic.connect(user3).approve(clientC.address, toTokenAmount(100));
        await ftm.connect(user3).approve(clientA.address, toTokenAmount(100));
        await ftm.connect(user3).approve(clientB.address, toTokenAmount(100));
        await ftm.connect(user3).approve(clientC.address, toTokenAmount(100));
        await bnb.connect(user3).approve(clientA.address, toTokenAmount(100));
        await bnb.connect(user3).approve(clientB.address, toTokenAmount(100));
        await bnb.connect(user3).approve(clientC.address, toTokenAmount(100));
        await usdc.connect(user3).approve(clientA.address, toTokenAmount(100));
        await usdc.connect(user3).approve(clientB.address, toTokenAmount(100));
        await usdc.connect(user3).approve(clientC.address, toTokenAmount(100));

        await matic.connect(user4).approve(clientA.address, toTokenAmount(100));
        await matic.connect(user4).approve(clientB.address, toTokenAmount(100));
        await matic.connect(user4).approve(clientC.address, toTokenAmount(100));
        await ftm.connect(user4).approve(clientA.address, toTokenAmount(100));
        await ftm.connect(user4).approve(clientB.address, toTokenAmount(100));
        await ftm.connect(user4).approve(clientC.address, toTokenAmount(100));
        await bnb.connect(user4).approve(clientA.address, toTokenAmount(100));
        await bnb.connect(user4).approve(clientB.address, toTokenAmount(100));
        await bnb.connect(user4).approve(clientC.address, toTokenAmount(100));
        await usdc.connect(user4).approve(clientA.address, toTokenAmount(100));
        await usdc.connect(user4).approve(clientB.address, toTokenAmount(100));
        await usdc.connect(user4).approve(clientC.address, toTokenAmount(100));

        await clientA.setPool(USDC, usdc.address, true);
        await clientA.setPool(MATIC, matic.address, true);
        await clientA.setPool(FTM, ftm.address, true);
        await clientA.setPool(BNB, bnb.address, true);

        await clientB.setPool(USDC, usdc.address, true);
        await clientB.setPool(MATIC, matic.address, true);
        await clientB.setPool(FTM, ftm.address, true);
        await clientB.setPool(BNB, bnb.address, true);

        await clientC.setPool(USDC, usdc.address, true);
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
        let matic_reserve = await core.pools(MATIC);
        console.log("MATIC");
        console.log(`interest rate: ${matic_reserve[0]} currentRatio: ${matic_reserve[1]} ceScaled: ${matic_reserve[4]}`)
        console.log(`dtScaled: ${matic_reserve[5]} ceSupply: ${matic_reserve[7]} debtSupply: ${matic_reserve[8]}`)

        let ftm_reserve = await core.pools(FTM);
        console.log("FTM");
        console.log(`interest rate: ${ftm_reserve[0]} currentRatio: ${ftm_reserve[1]} ceScaled: ${ftm_reserve[4]}`)
        console.log(`dtScaled: ${ftm_reserve[5]} ceSupply: ${ftm_reserve[7]} debtSupply: ${ftm_reserve[8]}`)

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

        console.log(`alice balance matic: ${balance_matic_alice} ftm: ${balance_ftm_alice} bnb: ${balance_bnb_alice}`)
        console.log(`bob balance matic: ${balance_matic_bob} ftm: ${balance_ftm_bob} bnb: ${balance_bnb_bob}`)

        let factor = await core.healthFactor(alice.address);
        console.log(`alice health factor collateral:${factor[0]} debt:${factor[1]} factor:${factor[2]} lts:${factor[3]}`)
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

    describe("1. Testing setting of functions of Branch contract ", () => {

        it("Only authorized can configure role manager address", async()=>{

            expect(await clientA.roleManager()).to.equal(roleManagerA.address);
            await expect(clientA.connect(alice).setRoleManager(feeProvider.address)).to.be.reverted;
            await clientA.connect(developer).setRoleManager(feeProvider.address);
            expect(await clientA.roleManager()).to.equal(feeProvider.address);

        })

        it("Only authorised can configure adapter contract", async () => {

            expect(await clientA.adapter()).to.equal(adapterA.address);
            await expect(clientA.connect(alice).setAdapter(roleManagerS.address)).to.be.reverted;
            await clientA.connect(developer).setAdapter(roleManagerS.address);
            expect(await clientA.adapter()).to.equal(roleManagerS.address);

        });

        it("Only authorized can toggle the status of the protocol on and off", async () => {

            expect(await clientA.protocolPause()).to.equal(false);
            await expect(clientA.connect(alice).toggleProtocolStatus()).to.be.reverted;
            await clientA.connect(developer).toggleProtocolStatus();
            expect(await clientA.protocolPause()).to.equal(true);

        })

        it("Only authorized can configure branch status for deposit", async () => {

            expect(await clientA.depositPause(MATIC)).to.equal(false);
            await expect(clientA.connect(alice).setDepositPause(MATIC,true)).to.be.reverted;
            await clientA.connect(developer).setDepositPause(MATIC,true);
            expect(await clientA.depositPause(MATIC)).to.equal(true);
        
        })

        it("Only authorized can configure branch status for repay", async () => {

            expect(await clientA.repayPause(FTM)).to.equal(false);
            await expect(clientA.connect(alice).setRepayPause(FTM,true)).to.be.reverted;
            await clientA.connect(developer).setRepayPause(FTM,true);
            expect(await clientA.repayPause(FTM)).to.equal(true);

        })

        it("Should set the forwarder address", async() => {

            await expect(clientA.connect(alice).setForwarder(roleManagerS.address)).to.be.reverted;
            await clientA.connect(developer).setForwarder(roleManagerS.address);
            expect(await clientA._trustedForwarder()).to.equal(roleManagerS.address);

        })

        it("Should set pool for an asset", async () => {

            await expect(clientA.connect(alice).setPool(FTM, ftm.address, true)).to.be.reverted;
            await clientA.connect(developer).setPool(FTM, ftm.address, true);
            const poolInfo = await clientA.pools(FTM);
            expect(poolInfo.token).to.equal(ftm.address);
            expect(poolInfo.enable).to.equal(true);

          });
          
        it("Should convert address to bytes32", async() => {
            
            //testing for contract address
            const testAddressRouteA = routeA.address;
            const resultRouteA = await clientA.addressToBytes32(testAddressRouteA);
            //result has leading 24 zeros and then the actual address i.e. 0x(24 zeros)(testAddressRouteA)
            //checking is done by trimming leading zeros
            const convertedRouteA = resultRouteA.substring(26).toLowerCase();
            const expectedRouteA = testAddressRouteA.toString().substring(2).toLowerCase()
            expect(convertedRouteA).to.equal(expectedRouteA);

            //testing for account address
            const testAddressDeveloper = developer.address;
            const resultDeveloper = await clientA.addressToBytes32(testAddressDeveloper);
            const convertedDeveloper = resultDeveloper.substring(26).toLowerCase();
            const expectedDeveloper = testAddressDeveloper.toString().substring(2).toLowerCase()
            expect(convertedDeveloper).to.equal(expectedDeveloper);

        })

        it("Should set stargate vault and router address", async() => {

            const stargateRouterAddress = "0xbf22f0f184bCcbeA268dF387a49fF5238dD23E40"; //stargate eth router address  
            const stargateVaultAddress = "0x82CbeCF39bEe528B5476FE6d1550af59a9dB6Fc0";  //stargate eth vault address 
            await expect(clientA.connect(alice).setStargateRouterAndVault(stargateRouterAddress,stargateVaultAddress)).to.be.reverted;
            await clientA.connect(developer).setStargateRouterAndVault(stargateRouterAddress,stargateVaultAddress);
            expect(await clientA.stargateRouter()).to.equal(stargateRouterAddress);
            expect(await clientA.stargateEthVault()).to.equal(stargateVaultAddress);

        })

    });


    describe("2. Testing setting of functions of Adapter contract", () => {

        it("Should set the roleManager address", async() => {

            await adapterA.connect(developer).setRoleManager(roleManagerA.address);
            const updatedRoleManagerAddress = await adapterA.roleManager();
            assert.equal(updatedRoleManagerAddress,roleManagerA.address);

        })

        //checking if branch address is set up correctly in the branch adapter
        it("Should configure the branch contract", async () => {

            await adapterA.connect(developer).setBranch(clientA.address);
            const updatedBranchAddress = await adapterA.branch();
            assert.equal(updatedBranchAddress, clientA.address);

        })

        //checking if route address is set up correctly in the branch adapter
        it("Should configure route address for corresponding route", async () => {

            await adapterA.connect(developer).setRoute(LZO, routeA.address);
            const updatedRouteAddress = await adapterA.router(LZO);
            expect(updatedRouteAddress).to.equal(routeA.address);
            expect(await adapterA.routeExist(routeA.address)).to.equal(true);

        })

    })
    
    describe("3. Testing the deposit ", async () => {

        it("Testing deposit in the same pool from different chain", async function () {

        let feesA = await routeA.connect(alice).estimateFees(1,0);
        await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(20), LZO, 0, { value: feesA })
        await clientB.connect(alice).depositRequest(MATIC, toTokenAmount(20), LZO, 0, { value: feesA })
        await clientC.connect(alice).depositRequest(MATIC, toTokenAmount(30), LZO, 0, { value: feesA })
        let alice_balance = await ceMATIC.balanceOf(alice.address);
        expect(alice_balance).to.equal("70000000000000000000");

        })

        it("Testing the CeSupply", async function () {

            let feesA = await routeA.connect(alice).estimateFees(1, 0);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(20), LZO, 0, { value: feesA })
            await clientB.connect(bob).depositRequest(MATIC, toTokenAmount(20), LZO, 0, { value: feesA })
            let matic_reserve = await core.pools(MATIC);
            expect(matic_reserve[7]).to.equal("40000000000000000000");
            
        })

        it("Testing liquidity in different chain of same pool", async function () {

            let feesA = await routeA.connect(alice).estimateFees(1, 0);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(2), LZO, 0, { value: feesA })
            await clientB.connect(alice).depositRequest(MATIC, toTokenAmount(1), LZO, 0, { value: feesA })
            await clientC.connect(alice).depositRequest(MATIC, toTokenAmount(3), LZO, 0, { value: feesA })
            let alice_balance = await ceMATIC.balanceOf(alice.address);
            expect(alice_balance).to.equal("6000000000000000000");
            let maticChainPoolliquidity = await core.chainLiquidity(MATIC,MATIC);
            let bnbChainPoolliquidity = await core.chainLiquidity(BNB,MATIC);
            let ftmChainPoolliquidity = await core.chainLiquidity(FTM,MATIC);
            expect(ftmChainPoolliquidity).to.equal("2000000000000000000");
            expect(bnbChainPoolliquidity).to.equal("1000000000000000000");
            expect(maticChainPoolliquidity).to.equal("3000000000000000000");
            
        })
        
        
    });

    describe("Testing the depositRequest function inside branch.sol contract", () => {  

        it("Should revert if the protocol is paused", async () => {
            expect(await clientA.protocolPause()).to.equal(false);
            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees });
            await clientA.connect(developer).toggleProtocolStatus();
            expect(await clientA.protocolPause()).to.equal(true);
            await expect (clientA.connect(alice).depositRequest(MATIC,toTokenAmount(10),LZO,0,{value: fees})).to.be.revertedWithCustomError(clientA,"ProtocolPaused").withArgs("Branch")
        })

        it("Should revert if the deposit pause is enabled", async () => {
            expect(await clientA.depositPause(MATIC)).to.equal(false);
            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees });
            await clientA.connect(developer).setDepositPause(MATIC,true);
            expect(await clientA.depositPause(MATIC)).to.equal(true);
            await expect (clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees })).to.be.revertedWithCustomError(clientA,"DepositPaused").withArgs("Branch",MATIC)
        })

        it("Should revert if the pool is not enabled", async () => {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await expect(clientA.connect(alice).setPool(FTM, ftm.address, true)).to.be.reverted;
            await clientA.connect(developer).setPool(FTM, ftm.address, false);
            const poolInfo = await clientA.pools(FTM);
            expect(poolInfo.enable).to.equal(false);
            await expect (clientA.connect(alice).depositRequest(FTM, toTokenAmount(10), LZO, 0, { value: fees })).to.be.revertedWithCustomError(clientA,"PoolNotEnabled").withArgs("Branch",FTM)
            
        })  

        //events emitted check

        //Deposit
        it("Should emit Deposit event with args user,id,tokenAmount,route and airdropaAmount after successful deposit", async () => {
            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await expect(clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees })).to.emit(clientA,"Deposit").withArgs(alice.address,MATIC,toTokenAmount(10),LZO,0);
        })

        //SendToken
        it("Should emit SendToken event with args user, id and tokenAmount after successful deposit", async () => {
            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await expect(clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees })).to.emit(clientA,"SendToken").withArgs(alice.address,MATIC,toTokenAmount(10));
          
        })


    })

    describe("4. Testing the repay ", async () => {

        it("Testing the debt after a day", async function () {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees });
            await clientB.connect(bob).depositRequest(BNB, toTokenAmount(10), LZO, 0, { value: fees });
            await pool.connect(alice).borrow(BNB, BNB, toTokenAmount(5), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees });
            await network.provider.send("evm_increaseTime", [1* 24 * 60 * 60]);
            await network.provider.send("evm_mine");
            let alicefactor = await core.healthFactor(alice.address);
            expect(alicefactor[1]).to.equal(5001369863013698630n);
    
        })

        it("Testing the debt after a week", async function () {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees });
            await clientB.connect(bob).depositRequest(BNB, toTokenAmount(10), LZO, 0, { value: fees });
            await pool.connect(alice).borrow(BNB, BNB, toTokenAmount(5), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees });
            await network.provider.send("evm_increaseTime", [7* 24 * 60 * 60]);
            await network.provider.send("evm_mine");
            let alicefactor = await core.healthFactor(alice.address);
            expect(alicefactor[1]).to.equal(5009589041095890410n);
    
        })

        it("Testing the debt after a full repay", async function () {

            let fees = await routeA.connect(alice).estimateFees(1, 10);
            await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(10), LZO, 0, { value: fees });
            let alicefactors = await core.healthFactor(alice.address);
            await clientB.connect(bob).depositRequest(BNB, toTokenAmount(10), LZO, 0, { value: fees });
            await pool.connect(alice).borrow(BNB, BNB, toTokenAmount(5), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees });
            await clientA.connect(alice).repayRequest(BNB, toTokenAmount(5.003), LZO, 0, { value: fees })
            let alicefactor = await core.healthFactor(alice.address);
            expect(alicefactor[1]).to.equal(0);

    
        })
        

    });
    
})