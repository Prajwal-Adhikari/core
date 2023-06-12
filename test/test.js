const { assert, expect } = require("chai")
const { ethers, upgrades } = require("hardhat")

let BN = require("bignumber.js");
const { keccak256 } = require("ethers/lib/utils");
const {BigNumber} = require("ethers");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}
// import { buildLiquidateParam } from './math.js';
// const {} = require('./math');
const {buildLiquidateParam} = require('./math.ts');


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
describe("Ready", function () {

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
        ceMATIC = await upgrades.deployProxy(CEToken,["CEMATIC", "CEMATIC", roleManagerS.address]);
        ceFTM = await upgrades.deployProxy(CEToken,["CEFTM", "CEFTM", roleManagerS.address]);
        ceBNB = await upgrades.deployProxy(CEToken,["CEBNB", "CEBNB", roleManagerS.address]);
        ceUSDC = await upgrades.deployProxy(CEToken,["CEUSDC", "CEUSDC", roleManagerS.address]);

        const DebtToken = await ethers.getContractFactory("DebtToken");
        debtMATIC = await upgrades.deployProxy(DebtToken,["DebtMATIC", "DebtMATIC", roleManagerS.address]);
        debtFTM = await upgrades.deployProxy(DebtToken,["DebtFTM", "DebtFTM", roleManagerS.address]);
        debtBNB = await upgrades.deployProxy(DebtToken,["DebtBNB", "DebtBNB", roleManagerS.address]);
        debtUSDC = await upgrades.deployProxy(DebtToken,["DebtUSDC", "DebtUSDC", roleManagerS.address]);
    
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
        routeA = await upgrades.deployProxy(Route, [this.lzEndpointMockClientA.address, this.chainIdClientA, this.chainIdServer, 400000, roleManagerA.address]);
        routeB = await upgrades.deployProxy(Route, [this.lzEndpointMockClientB.address, this.chainIdClientB, this.chainIdServer, 400000, roleManagerB.address]);
        routeC = await upgrades.deployProxy(Route, [this.lzEndpointMockClientC.address, this.chainIdClientC, this.chainIdServer, 400000, roleManagerC.address]);

        const Server = await ethers.getContractFactory("Pool");
        pool = await upgrades.deployProxy(Server, [treasury.address, roleManagerS.address]);

        // Server Adapter
        const AdapterPool = await ethers.getContractFactory("AdapterPool");
        adapterS = await upgrades.deployProxy(AdapterPool, [roleManagerS.address]);

        

        const Core = await ethers.getContractFactory("Core");
        core = await upgrades.deployProxy(Core, [treasury.address, roleManagerS.address]);

        // Server Route
        const LzRoutePool = await ethers.getContractFactory("LzRoutePool");
        routeS = await upgrades.deployProxy(LzRoutePool, [this.lzEndpointMockServer.address, this.chainIdServer, 200000, roleManagerS.address]);

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

        // alice account only has the permission to init pool
        await core.connect(alice).initPool(MATIC, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(1), toTokenAmount(0.15)], ceMATIC.address, debtMATIC.address);
        await core.connect(alice).initPool(FTM, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(1), toTokenAmount(0.15)], ceFTM.address, debtFTM.address);
        await core.connect(alice).initPool(BNB, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(1), toTokenAmount(0.15)], ceBNB.address, debtBNB.address);
        await core.connect(alice).initPool(USDC, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(1), toTokenAmount(0.15)], ceUSDC.address, debtUSDC.address);


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

        await matic.mint(alice.address, toTokenAmount(1e6))
        await ftm.mint(alice.address, toTokenAmount(1e6))
        await bnb.mint(alice.address, toTokenAmount(1e6))
        await usdc.mint(alice.address, toTokenAmount(1e6, 6))

        await matic.mint(bob.address, toTokenAmount(1e6))
        await ftm.mint(bob.address, toTokenAmount(1e6))
        await bnb.mint(bob.address, toTokenAmount(1e6))
        await usdc.mint(bob.address, toTokenAmount(1e6, 6))

        await matic.mint(user3.address, toTokenAmount(1e6))
        await ftm.mint(user3.address, toTokenAmount(1e6))
        await bnb.mint(user3.address, toTokenAmount(1e6))
        await usdc.mint(user3.address, toTokenAmount(1e6, 6))

        await matic.mint(user4.address, toTokenAmount(1e6))
        await ftm.mint(user4.address, toTokenAmount(1e6))
        await bnb.mint(user4.address, toTokenAmount(1e6))
        await usdc.mint(user4.address, toTokenAmount(1e6, 6))

        await matic.connect(alice).approve(clientA.address, toTokenAmount(1e6));
        await matic.connect(alice).approve(clientB.address, toTokenAmount(1e6));
        await matic.connect(alice).approve(clientC.address, toTokenAmount(1e6));
        await ftm.connect(alice).approve(clientA.address, toTokenAmount(1e6));
        await ftm.connect(alice).approve(clientB.address, toTokenAmount(1e6));
        await ftm.connect(alice).approve(clientC.address, toTokenAmount(1e6));
        await bnb.connect(alice).approve(clientA.address, toTokenAmount(1e6));
        await bnb.connect(alice).approve(clientB.address, toTokenAmount(1e6));
        await bnb.connect(alice).approve(clientC.address, toTokenAmount(1e6));

        await usdc.connect(alice).approve(clientA.address, toTokenAmount(1e6));
        await usdc.connect(alice).approve(clientB.address, toTokenAmount(1e6));
        await usdc.connect(alice).approve(clientC.address, toTokenAmount(1e6));

        await matic.connect(bob).approve(clientA.address, toTokenAmount(1e6));
        await matic.connect(bob).approve(clientB.address, toTokenAmount(1e6));
        await matic.connect(bob).approve(clientC.address, toTokenAmount(1e6));
        await ftm.connect(bob).approve(clientA.address, toTokenAmount(1e6));
        await ftm.connect(bob).approve(clientB.address, toTokenAmount(1e6));
        await ftm.connect(bob).approve(clientC.address, toTokenAmount(1e6));
        await bnb.connect(bob).approve(clientA.address, toTokenAmount(1e6));
        await bnb.connect(bob).approve(clientB.address, toTokenAmount(1e6));
        await bnb.connect(bob).approve(clientC.address, toTokenAmount(1e6));
        await usdc.connect(bob).approve(clientA.address, toTokenAmount(1e6));
        await usdc.connect(bob).approve(clientB.address, toTokenAmount(1e6));
        await usdc.connect(bob).approve(clientC.address, toTokenAmount(1e6));
        
        await matic.connect(user3).approve(clientA.address, toTokenAmount(1e6));
        await matic.connect(user3).approve(clientB.address, toTokenAmount(1e6));
        await matic.connect(user3).approve(clientC.address, toTokenAmount(1e6));
        await ftm.connect(user3).approve(clientA.address, toTokenAmount(1e6));
        await ftm.connect(user3).approve(clientB.address, toTokenAmount(1e6));
        await ftm.connect(user3).approve(clientC.address, toTokenAmount(1e6));
        await bnb.connect(user3).approve(clientA.address, toTokenAmount(1e6));
        await bnb.connect(user3).approve(clientB.address, toTokenAmount(1e6));
        await bnb.connect(user3).approve(clientC.address, toTokenAmount(1e6));
        await usdc.connect(user3).approve(clientA.address, toTokenAmount(1e6));
        await usdc.connect(user3).approve(clientB.address, toTokenAmount(1e6));
        await usdc.connect(user3).approve(clientC.address, toTokenAmount(1e6));

        await matic.connect(user4).approve(clientA.address, toTokenAmount(1e6));
        await matic.connect(user4).approve(clientB.address, toTokenAmount(1e6));
        await matic.connect(user4).approve(clientC.address, toTokenAmount(1e6));
        await ftm.connect(user4).approve(clientA.address, toTokenAmount(1e6));
        await ftm.connect(user4).approve(clientB.address, toTokenAmount(1e6));
        await ftm.connect(user4).approve(clientC.address, toTokenAmount(1e6));
        await bnb.connect(user4).approve(clientA.address, toTokenAmount(1e6));
        await bnb.connect(user4).approve(clientB.address, toTokenAmount(1e6));
        await bnb.connect(user4).approve(clientC.address, toTokenAmount(1e6));
        await usdc.connect(user4).approve(clientA.address, toTokenAmount(1e6));
        await usdc.connect(user4).approve(clientB.address, toTokenAmount(1e6));
        await usdc.connect(user4).approve(clientC.address, toTokenAmount(1e6));

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

    /*
    it("test not 18 decimals", async function() {
        let fees = await routeA.connect(alice).estimateFees(1, 1000000);
        console.log("alice deposit usdc");
        await clientA.connect(alice).depositRequest(USDC, 1000000, LZO, 0, { value: fees })
        let ce_balance = await ceUSDC.balanceOf(alice.address);
        let usdc_balance = await usdc.balanceOf(alice.address);
        assert.equal(ce_balance, toTokenAmount(1));
        assert.equal(usdc_balance, 99e6);

        console.log("alice withdraw usdc")
        await pool.connect(alice).withdraw(USDC, FTM, toTokenAmount(0.5), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees })
        ce_balance = await ceUSDC.balanceOf(alice.address);
        usdc_balance = await usdc.balanceOf(alice.address);
        assert.equal(ce_balance, toTokenAmount(0.5));
        assert.equal(usdc_balance, 99.5e6);
    })
    */

    it("test liquidation", async function() {
        let fees = await routeA.connect(alice).estimateFees(1, 1000000);
        //alice is borrower
        //bob is liquidator

        //debtPool.debtToken = debtFTM
        //debtPool.ceToken = ceFTM
        //collateralPool.ceToken = ceMATIC

        console.log("alice deposit matic");
        await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(5e5), LZO, 0, { value: fees })
        
        console.log("bob deposit ftm");
        await clientB.connect(bob).depositRequest(FTM, toTokenAmount(5e5), LZO, 0, { value: fees })
        
        console.log("alice borrow ftm");
        await pool.connect(alice).borrow(FTM, BNB, toTokenAmount(2e5), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees });
   
        console.log("increase ftm price in oracle");
        await this.oracle.setPrice( [FTM], [toTokenAmount(2)])

        console.log("check alice health factor");
        hfb = await core.healthFactor(alice.address);
        console.log("can liquidate", hfb.factor >= 1e18);

        let alice_debt_before = await debtFTM.balanceOf(alice.address);
        let bob_ce_before = await ceFTM.balanceOf(bob.address);
        let alice_collateral_before = await ceMATIC.balanceOf(alice.address);
        let bob_collateral_before = await ceMATIC.balanceOf(bob.address);

        let currentLTV =  (hfb.debtValue * 1e18)/hfb.collateralValue;
        let data = await buildLiquidateParam(currentLTV, MATIC, FTM, 1e4, core, this.oracle);
        // console.log(data);
        // make the function public if needed to check data and data2
        // let data2 = await liquidationManager.buildLiquidateParams( MATIC, FTM, 100000, BigNumber.from("250999996829020670"))
        // console.log(data2);

        console.log("bob will liquidate");
        await liquidationManager.connect(bob).liquidate(alice.address, MATIC, FTM, toTokenAmount(1e4));
     
        let alice_debt_after= await debtFTM.balanceOf(alice.address);
        let bob_ce_after = await ceFTM.balanceOf(bob.address);
        let alice_collateral_after = await ceMATIC.balanceOf(alice.address);
        let bob_collateral_after = await ceMATIC.balanceOf(bob.address);

        let difference_debt_alice = alice_debt_before - alice_debt_after;
        let difference_ce_bob = bob_ce_before - bob_ce_after;
        let difference_collateral_alice = alice_collateral_before - alice_collateral_after;
        let difference_collateral_bob = bob_collateral_after - bob_collateral_before;

        // console.log(difference_debt_alice);
        // console.log(difference_ce_bob);
        // console.log(difference_collateral_alice);
        // console.log(difference_collateral_bob);

        //NOTE: Due to arithmatics done on large numbers the numbers will have some decimals mismatched as expected 
        //as a result checking > or = as needed.
        
        //dbtoken of alice burn by burnBorrowerDebtAmount
        console.log(Math.round(data.burnBorrowerDebtAmount) *10**18, " almost equal ~", difference_debt_alice);
        assert.isAbove(Math.round(data.burnBorrowerDebtAmount) *10**18, difference_debt_alice);
        //cetoekn of bob burn by burnLiquidatorCEAmount
        console.log(Math.round(data.burnLiquidatorCEAmount) *10**18, " almost equal ~", difference_ce_bob);
        assert.isAbove(Math.round(data.burnLiquidatorCEAmount) *10**18, difference_ce_bob);
        //cetoken of alice burn by liqBorrowerCEAmount
        console.log(Math.round(data.liqBorrowerCEAmount) *10**18, " almost equal ~", difference_collateral_alice);
        assert.isAbove(Math.round(data.liqBorrowerCEAmount) *10**18, difference_collateral_alice);
        //cetoken if bob mint by liqBorrowerCEAmount
        assert.equal(Math.round(data.liqBorrowerCEAmount) *10**18, difference_collateral_bob);

    })

    /*
    it("test ceToken transfer", async function() {
        let fees = await routeA.connect(alice).estimateFees(1, 1000000);

        console.log("alice deposit matic");
        await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(500000), LZO, 0, { value: fees })

        console.log("bob deposit ftm");
        await clientB.connect(bob).depositRequest(FTM, toTokenAmount(5e5), LZO, 0, { value: fees })

        console.log("alice borrow ftm and after one year");
        await pool.connect(alice).borrow(FTM, BNB, toTokenAmount(1e5), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees });
        await network.provider.send("evm_increaseTime", [365 * 86400])

        console.log("alice repay ftm")
        // await expect(pool.connect(alice).withdraw(MATIC, FTM, toTokenAmount(263550), {value: fees})).to.be.revertedWith("Health check failed");
        await clientB.connect(alice).repayRequest(FTM, toTokenAmount(50000), LZO, 0, { value: fees })
        await printCEBalance();

        console.log("bob transfer ceToken to alice")
        await ceFTM.connect(bob).transfer(alice.address, toTokenAmount(100000))
        await printCEBalance();

        console.log("alice repay the remain ftm");
        await clientB.connect(alice).repayRequest(FTM, toTokenAmount(50000), LZO, 0, { value: fees })
        await printCEBalance();
    })


    it("Simple test", async function () {
        console.log("here");
        let fees = await routeA.connect(alice).estimateFees(1, 1000000);
        console.log(fees);

        console.log("alice deposit matic");
        await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(500000), LZO, 0, { value: fees })
        await printInfo();

        console.log("bob deposit ftm");
        await clientB.connect(bob).depositRequest(FTM, toTokenAmount(5e5), LZO, 0, { value: fees })
        await printInfo();

        console.log("alice borrow ftm and after one month");
        await pool.connect(alice).borrow(FTM, BNB, toTokenAmount(1e5), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees });
        await network.provider.send("evm_increaseTime", [365 * 86400 - 1])
        await printInfo();

        console.log("alice withdraw matic and get revert");
        await expect(pool.connect(alice).withdraw(MATIC, FTM, toTokenAmount(5e5), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees })).to.be.revertedWith("Core: Health failed");

        console.log("alice withdraw matic");
        await pool.connect(alice).withdraw(MATIC, FTM, toTokenAmount(1e5), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees })
        await printInfo();

        console.log("bob withdraw ftm");
        await pool.connect(bob).withdraw(FTM, BNB, toTokenAmount(1e5), ethers.utils.hexZeroPad(bob.address, 32), LZO, 0, { value: fees })
        await printInfo();

        console.log("alice deposit bnb");
        await clientC.connect(alice).depositRequest(BNB, toTokenAmount(500000), LZO, 0, { value: fees })
        await printInfo();

        console.log("alice withdraw bnb");
        await pool.connect(alice).withdraw(BNB, MATIC, toTokenAmount(1e5), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees })
        await printInfo();

        console.log("alice withdraw matic")
        await pool.connect(alice).withdraw(MATIC, FTM, toTokenAmount(180000), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees })
        await printInfo();
        // expect(await matic.balanceOf(alice.address)).to.be.equal(toTokenAmount(6e5))

        await network.provider.send("evm_increaseTime", [365 * 86400])
        console.log("alice repay ftm")
        // await expect(pool.connect(alice).withdraw(MATIC, FTM, toTokenAmount(263550), {value: fees})).to.be.revertedWith("Health check failed");
        await clientB.connect(alice).repayRequest(FTM, toTokenAmount(50000), LZO, 0, { value: fees })
        await printInfo();

        await clientB.connect(alice).repayRequest(FTM, toTokenAmount(200000), LZO, 0, { value: fees })
        await printInfo();


        console.log("alice deposit matic");
        await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(500000), LZO, 0, { value: fees })
        await printInfo();

        console.log("bob borrow matic");
        await pool.connect(bob).borrow(MATIC, FTM, toTokenAmount(2e5), ethers.utils.hexZeroPad(bob.address, 32), LZO, 0, { value: fees });
        await network.provider.send("evm_increaseTime", [365 * 86400 - 1])
        await printInfo();

        console.log("liquidate test");
        await liquidationManager.connect(alice).liquidate(bob.address, FTM, MATIC, toTokenAmount(50000));
        await printInfo();
    })
    */

    /*
    it("EQ FEE test", async function () {

        await feeProvider.configureOptimalGlobalLiquidityFactor([FTM,BNB,MATIC], [MATIC, MATIC, MATIC], [toTokenAmount(0.3),toTokenAmount(0.3),toTokenAmount(0.4)]);
        await feeProvider.configureBaseFee([FTM,BNB,MATIC], [MATIC, MATIC, MATIC], [toTokenAmount(1),toTokenAmount(1),toTokenAmount(1)]);
        await feeProvider.configureMaxFee([FTM,BNB,MATIC], [MATIC, MATIC, MATIC], [toTokenAmount(5),toTokenAmount(5),toTokenAmount(5)]);

        console.log("here");
        let fees = await routeA.connect(alice).estimateFees(1, 1000000);

        console.log("alice deposit matic from fantom chain");
        await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(2e5), LZO, 0, { value: fees })

        // console.log("bob deposit matic from fantom chain");
        await clientA.connect(bob).depositRequest(MATIC, toTokenAmount(2e5), LZO, 0, { value: fees })

        console.log("alice deposit matic from matic chain");
        await clientC.connect(alice).depositRequest(MATIC, toTokenAmount(3e5), LZO, 0, { value: fees })

        // console.log("bob deposit matic from matic chain");
        await clientC.connect(bob).depositRequest(MATIC, toTokenAmount(3e5), LZO, 0, { value: fees })

        console.log("alice borrow Matic from matic chain");
        await pool.connect(alice).borrow(MATIC, MATIC, toTokenAmount(2e5), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees });

        console.log("bob borrow Matic from fantom chain");
        await pool.connect(bob).borrow(MATIC, FTM, toTokenAmount(2e5), ethers.utils.hexZeroPad(bob.address, 32), LZO, 0, { value: fees });

        let fee1 = await core.getLiquidity(FTM, MATIC)
        console.log('total chain liquidity in fantom', fee1, " ", fee1/10**18);

        fee1 = await core.getLiquidity(MATIC, MATIC)
        console.log('total chain liquidity in matic', fee1, " ", fee1/10**18);

        let fee2 = await core.totalLiquidity(MATIC)
        console.log('total liquidity', fee2, " ", fee2/10**18);

        let glf = await feeProvider._getGlobalLiquidityFactor(FTM, MATIC)
        console.log('glf in fantom chain', glf, " ", glf/10**18);

        glf = await feeProvider._getGlobalLiquidityFactor(MATIC, MATIC)
        console.log('glf in matic chain', glf, " ", glf/10**18);
        
        let feeP1 = await feeProvider.getFeeAmount(FTM, MATIC);
        console.log('fee amount in fantom chain', feeP1, " ", feeP1/10**18);

        feeP1 = await feeProvider.getFeeAmount(MATIC, MATIC);
        console.log('fee amount in matic chain',feeP1, " ", feeP1/10**18);

    })
    */

    // it("Test reward", async function () {
    //     let fees = await routeA.connect(alice).estimateFees(MATIC);

    //     await pool.setFeeRewardStatus(true, true);

    //     await this.cedro.transfer(pool.address, toTokenAmount(500000));

    //     let balance_matic_client = await matic.balanceOf(clientA.address);
    //     console.log("Before balance of matic pool", balance_matic_client.toString(), clientA.address);

    //     await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(500000), {value: fees});

    //     console.log("Alice gets cedro reward");
    //     let balance = await this.cedro.balanceOf(alice.address);
    //     console.log("reward", balance.toString(), alice.address);
    //     // expect(balance).to.equal(toTokenAmount(1));

    //     balance = await this.cedro.balanceOf(pool.address);
    //     console.log("remaining balance", balance.toString(), pool.address);

    //     await printInfo();

    //     balance_matic_client = await matic.balanceOf(clientA.address);
    //     console.log("After balance of matic pool", balance_matic_client.toString(), clientA.address);

    //     balance = await ceMATIC.balanceOf(alice.address);
    //     console.log("CEtoken", balance.toString(), alice.address);
    //     // expect(balance).to.equal(toTokenAmount(500000));

    // })

    // it("USDC Decimal 6 and 9 Test", async function () {
    //     let fees = await routeA.connect(alice).estimateFees(1, 1000000);

    //     // const USDC2 = ethers.utils.formatBytes32String("USDC");
    //     const ERC20 = await ethers.getContractFactory("ERC20Mock")
    //     usdc2 = await ERC20.deploy("USDC", "USDC", 9)
    //     await usdc2.mint(alice.address, toTokenAmount(1e6))
    //     await usdc2.connect(alice).approve(clientA.address, toTokenAmount(1e6));
    //     //overwrite previous initialization
    //     await clientA.setPool(USDC, usdc2.address, true);

    //     await feeProvider.configureOptimalGlobalLiquidityFactor([FTM,BNB,MATIC], [USDC, USDC, USDC], [toTokenAmount(0.3),toTokenAmount(0.3),toTokenAmount(0.4)]);
    //     await feeProvider.configureBaseFee([FTM,BNB,MATIC], [USDC, USDC, USDC], [toTokenAmount(1),toTokenAmount(1),toTokenAmount(1)]);
    //     await feeProvider.configureMaxFee([FTM,BNB,MATIC], [USDC, USDC, USDC], [toTokenAmount(5),toTokenAmount(5),toTokenAmount(5)]);

    //     let aliceBalanceBefore = await usdc.balanceOf(alice.address);
    //     console.log('aliceBalance', aliceBalanceBefore);

    //     let usdc1Amount = 1e5
    //     console.log("bob deposit USDC1 from matic chain");
    //     await clientC.connect(bob).depositRequest(USDC, toTokenAmount(usdc1Amount, 6), LZO, 0, { value: fees })
        
    //     let usdc2Amount = 2e5
    //     console.log("alice deposit USDC2 from fantom chain");
    //     await clientA.connect(alice).depositRequest(USDC, toTokenAmount(usdc2Amount, 9), LZO, 0, { value: fees })

    //     // let amount = await clientC._buildRemoteAmount(toTokenAmount(1e5, 6), usdc.address);
    //     // console.log(amount);

    //     // amount = await clientA._buildRemoteAmount(toTokenAmount(2e5, 9), usdc2.address);
    //     // console.log(amount);

    //     let fee1 = await core.getLiquidity(MATIC, USDC)
    //     console.log('total chain liquidity in matic', fee1, " ", fee1/10**18);
    //     assert.equal(usdc1Amount * 10 **18, fee1)

    //     fee1 = await core.getLiquidity(FTM, USDC)
    //     console.log('total chain liquidity in FTM', fee1, " ", fee1/10**18);
    //     assert.equal(usdc2Amount * 10 **18, fee1)

    //     let fee2 = await core.totalLiquidity(USDC)
    //     console.log('total liquidity', fee2, " ", fee2/10**18);
    //     assert.equal((usdc1Amount + usdc2Amount) * 10 **18, fee2)

    //     //alice withdraw to fantom chain
    //     console.log("bob withdraw to ftm chain");
    //     await pool.connect(bob).withdraw( USDC, FTM, toTokenAmount(usdc1Amount), ethers.utils.hexZeroPad(bob.address, 32), LZO, 0, { value: fees })
    
    //     // alice withdraw to matic chain
    //     console.log("alice withdraw to matic chain");
    //     await pool.connect(alice).withdraw(USDC, MATIC, toTokenAmount(usdc1Amount), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees })

    //     fee1 = await core.getLiquidity(MATIC, USDC)
    //     // console.log('total chain liquidity in matic', fee1, " ", fee1/10**18);
    //     assert.equal(fee1, 0)

    //     fee1 = await core.getLiquidity(FTM, USDC)
    //     // console.log('total chain liquidity in FTM', fee1, " ", fee1/10**18);
    //     assert.equal(usdc1Amount * 10 **18, fee1)

    //     fee2 = await core.totalLiquidity(USDC)
    //     // console.log('total liquidity', fee2, " ", fee2/10**18);
    //     assert.equal((usdc1Amount) * 10 **18, fee2)

    //     bobBalance = await usdc2.balanceOf(bob.address);
    //     // console.log('bobBalance', bobBalance);
    //     assert.equal(bobBalance, usdc1Amount * 10**9)

    //     let aliceBalanceAfter = await usdc.balanceOf(alice.address);
    //     console.log('aliceBalance', aliceBalanceAfter);
    //     assert.equal(aliceBalanceAfter.toNumber(),  aliceBalanceBefore.toNumber() + (usdc1Amount * 10**6))
    // })    

    // it("USDC Decimal 18 and 21 Test", async function () {
    //     let fees = await routeA.connect(alice).estimateFees(1, 1000000);
            // matic2 = await ERC20.deploy("MATIC", "MATIC", 21)
            // // await matic2.mint(alice.address, toTokenAmount(5e6, 21))
            // await matic2.connect(alice).approve(clientA.address, toTokenAmount(1e6, 21));
            // //overwrite previous initialization
            // await clientA.setPool(MATIC, matic2.address, true);

    //     let poolinfo = await clientA.pools(MATIC)
    //     console.log(poolinfo, " ", matic2.address);
        
    //     let alice2BalanceBefore = await matic2.balanceOf(alice.address);
    //     console.log('alice2BalanceB', alice2BalanceBefore);

    //     let clientA2BalanceB = await matic2.balanceOf(clientA.address);
    //     console.log('clientA2BalanceB', clientA2BalanceB);

    //     let alice1BalanceBefore = await matic.balanceOf(alice.address);
    //     console.log('alice1BalanceB', alice1BalanceBefore);

    //     let ceTokenAliceBefore = await ceMATIC.balanceOf(alice.address);
    //     console.log('ceTokenAliceBefore', ceTokenAliceBefore);

    //     await feeProvider.configureOptimalGlobalLiquidityFactor([FTM,BNB,MATIC], [USDC, USDC, USDC], [toTokenAmount(0.3),toTokenAmount(0.3),toTokenAmount(0.4)]);
    //     await feeProvider.configureBaseFee([FTM,BNB,MATIC], [USDC, USDC, USDC], [toTokenAmount(1),toTokenAmount(1),toTokenAmount(1)]);
    //     await feeProvider.configureMaxFee([FTM,BNB,MATIC], [USDC, USDC, USDC], [toTokenAmount(5),toTokenAmount(5),toTokenAmount(5)]);

    //     let usdc2Amount = 2e5
    //     console.log("alice deposit matic2 from fantom chain");
    //     await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(usdc2Amount, 21), LZO, 0, { value: fees })

    //     let usdc1Amount = 1e5
    //     console.log("bob deposit matic1 from matic chain");
    //     await clientC.connect(bob).depositRequest(MATIC, toTokenAmount(usdc1Amount), LZO, 0, { value: fees })

    //     let clientA2BalanceA = await matic2.balanceOf(clientA.address);
    //     console.log('clientA2BalanceA', clientA2BalanceA);

    //     let aliceBalanceA = await matic2.balanceOf(alice.address);
    //     console.log('alice2BalanceA', aliceBalanceA);

    //     let alice1BalanceA= await matic.balanceOf(alice.address);
    //     console.log('alice1BalanceA', alice1BalanceA);

    //     let ceTokenAliceAfter= await ceMATIC.balanceOf(alice.address);
    //     console.log('ceTokenAliceAfter', ceTokenAliceAfter);

    //     // let amount = await clientC._buildRemoteAmount(toTokenAmount(1e5), matic.address);
    //     // console.log(amount);

    //     // amount = await clientA._buildRemoteAmount(toTokenAmount(2e5, 21), matic2.address);
    //     // console.log(amount);

    //     let fee1 = await core.getLiquidity(MATIC, MATIC)
    //     console.log('total chain liquidity in matic', fee1, " ", fee1/10**18);
    //     // assert.equal(usdc1Amount * 10 **18, fee1)

    //     fee1 = await core.getLiquidity(FTM, MATIC)
    //     console.log('total chain liquidity in FTM', fee1, " ", fee1/10**18);
    //     // assert.equal(usdc2Amount * 10 **18, fee1)

    //     let fee2 = await core.totalLiquidity(MATIC)
    //     console.log('total liquidity', fee2, " ", fee2/10**18);
    //     // assert.equal((usdc1Amount + usdc2Amount) * 10 **18, fee2)

    //     //alice withdraw to fantom chain
    //     console.log("bob withdraw to ftm chain");
    //     await pool.connect(bob).withdraw(MATIC, FTM, toTokenAmount(usdc1Amount), ethers.utils.hexZeroPad(bob.address, 32), LZO, 0, { value: fees })
    
    //     // alice withdraw to matic chain
    //     console.log("alice withdraw to matic chain");
    //     await pool.connect(alice).withdraw(MATIC, MATIC, toTokenAmount(usdc1Amount), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees })

    //     fee1 = await core.getLiquidity(MATIC, MATIC)
    //     console.log('total chain liquidity in matic', fee1, " ", fee1/10**18);
    //     // assert.equal(fee1, 0)

    //     fee1 = await core.getLiquidity(FTM, MATIC)
    //     console.log('total chain liquidity in FTM', fee1, " ", fee1/10**18);
    //     // assert.equal(usdc1Amount * 10 **18, fee1)

    //     fee2 = await core.totalLiquidity(MATIC)
    //     console.log('total liquidity', fee2, " ", fee2/10**18);
    //     // assert.equal((usdc1Amount) * 10 **18, fee2)

    //     let bobBalance = await matic2.balanceOf(bob.address);
    //     console.log('bobBalance', bobBalance);
    //     // assert.equal(bobBalance, usdc1Amount * 10**9)

    //     let aliceBalanceAfter = await matic.balanceOf(alice.address);
    //     console.log('aliceBalance', aliceBalanceAfter);
    //     // console.log(aliceBalanceAfter.toNumber(), " ",  aliceBalanceBefore.toNumber() ," ",  (usdc1Amount * 10**18))
    // })  
})
