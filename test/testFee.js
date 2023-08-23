const { assert, expect } = require("chai")
const chai = require('chai');
const chaiAlmost = require('chai-almost');

chai.use(chaiAlmost());
const { ethers, upgrades } = require("hardhat")
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
chai.use(chaiAlmost());

let BN = require("bignumber.js");
const { keccak256 } = require("ethers/lib/utils");
const {BigNumber} = require("ethers");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}
// import { buildLiquidateParam } from './math.js';
// const {} = require('./math');
const {buildLiquidateParam} = require('./math.ts');
const { parse } = require("dotenv");


const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();

const MATIC = ethers.utils.formatBytes32String("MATIC");
const FTM = ethers.utils.formatBytes32String("FTM");
const BNB = ethers.utils.formatBytes32String("BNB");
const USDC = ethers.utils.formatBytes32String("USDC");
const LZO = ethers.utils.formatBytes32String("LZO");

// Contracts
let pool, core, liquidationManager, treasury, feeProvider, controller;
let clientA, clientB, clientC, adapterA, adapterB, adapterC, adapterS, routeA, routeB, routeC, routeS, fees;
let roleManagerS, roleManagerA, roleManagerB, roleManagerC;
let matic, matic2, ftm, bnb, usdc, ceUSDC, ceFTM, ceBNB, ceMATIC, debtUSDC, debtFTM, debtBNB, debtMATIC;
let capturedAmount,poolWithLibraryABI;

const captureAmount = (value) => {
    capturedAmount = value;
    return true;
} 


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
        routeA = await upgrades.deployProxy(Route, [this.lzEndpointMockClientA.address, this.chainIdClientA, this.chainIdServer, 60000000, roleManagerA.address]);
        routeB = await upgrades.deployProxy(Route, [this.lzEndpointMockClientB.address, this.chainIdClientB, this.chainIdServer, 60000000, roleManagerB.address]);
        routeC = await upgrades.deployProxy(Route, [this.lzEndpointMockClientC.address, this.chainIdClientC, this.chainIdServer, 60000000, roleManagerC.address]);

        const Server = await ethers.getContractFactory("Pool");
        pool = await upgrades.deployProxy(Server, [treasury.address, roleManagerS.address]);

        // Server Adapter
        const AdapterPool = await ethers.getContractFactory("AdapterPool");
        adapterS = await upgrades.deployProxy(AdapterPool, [roleManagerS.address]);

        

        const Core = await ethers.getContractFactory("Core");
        core = await upgrades.deployProxy(Core, [treasury.address, roleManagerS.address]);

        // Server Route
        const LzRoutePool = await ethers.getContractFactory("LzRoutePool");
        routeS = await upgrades.deployProxy(LzRoutePool, [this.lzEndpointMockServer.address, this.chainIdServer, 60000000, roleManagerS.address]);

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
        await routeS.setRoute(LZO);

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
        await pool.toggleFeeEnable();
        await pool.toggleRewardEnable();
        await feeProvider.setCore(core.address);
        await feeProvider.configureOptimalGlobalLiquidityFactor(MATIC,[MATIC,FTM,BNB],[toTokenAmount(0.2),toTokenAmount(0.2),toTokenAmount(0.2)]);
        await feeProvider.configureOptimalGlobalLiquidityFactor(FTM,[MATIC,FTM,BNB],[toTokenAmount(0.2),toTokenAmount(0.2),toTokenAmount(0.2)]);
        await feeProvider.configureOptimalGlobalLiquidityFactor(BNB,[MATIC,FTM,BNB],[toTokenAmount(0.2),toTokenAmount(0.2),toTokenAmount(0.2)]);

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

        await matic.mint(alice.address, toTokenAmount(10e6))
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

        fees = await routeA.connect(alice).estimateFees(1, 0);

        //clientA = FTM clientB = BNB clientC = MATIC
        await clientA.connect(alice).depositRequest(MATIC, toTokenAmount(1e5), LZO, 0, { value: fees })
        await clientB.connect(bob).depositRequest(MATIC, toTokenAmount(1e5), LZO, 0, { value: fees })
        await clientC.connect(bob).depositRequest(MATIC, toTokenAmount(1e5), LZO, 0, { value: fees })

        poolWithLibraryABI = await ethers.getContractAt("Data", pool.address);

        
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

    it("No fee for withdraw till 60% of optimal balance", async function () {
        let totalLiquidity = await core.totalLiquidity(MATIC);
        let amount = await feeProvider.getWithdrawAbleAmountWithoutFee(BNB,MATIC);
        console.log(amount);
        console.log("total",totalLiquidity);

        await expect(pool.connect(alice).withdraw(MATIC, BNB, amount, ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, false, { value: fees }))
                    .to.emit(poolWithLibraryABI,"Withdraw")
                    .withArgs(alice.address,alice.address,MATIC,BNB,amount,anyValue,LZO,captureAmount);

        expect(capturedAmount).to.equal(toTokenAmount(0));

    });

    it("Fee incurred for withdraw after 60% of optimal balance", async function () {

        let amount = await feeProvider.getWithdrawAbleAmountWithoutFee(BNB,MATIC);
        console.log(amount);

        //small extra amount drawn in addition to incurr fee
        amount = toTokenAmount(parseFloat(toMathAmount(amount)) + 0.001);
        console.log(amount);

        await expect(pool.connect(alice).withdraw(MATIC, BNB, amount, ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, false, { value: fees }))
                    .to.emit(poolWithLibraryABI,"Withdraw")
                    .withArgs(alice.address,alice.address,MATIC,BNB,anyValue,anyValue,LZO,captureAmount);

        //negligible amount of fee incured
        expect((capturedAmount)).to.almost.equal(toTokenAmount(1.54879e-13));

    });

    it("Fee incurred for withdrawing all liquidity of a chain", async function () {

        // Withdrawing all Liquidity from chain
        let beforeLiquidity = await core.getLiquidity(BNB,MATIC);

        console.log(beforeLiquidity);

        await expect(pool.connect(alice).withdraw(MATIC, BNB, beforeLiquidity, ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, false, { value: fees }))
                    .to.emit(poolWithLibraryABI,"Withdraw")
                    .withArgs(alice.address,alice.address,MATIC,BNB,anyValue,anyValue,LZO,captureAmount);

        //Max amount of fee 
        expect((capturedAmount)).to.almost.equal(toTokenAmount(1120));
        let afterLiquidity = await core.getLiquidity(BNB,MATIC);
        expect((afterLiquidity)).to.equal(toTokenAmount(0));



    });

    it("No reward for deposit until fee has incurred", async function () {
        let amount = await feeProvider.getWithdrawAbleAmountWithoutFee(BNB,MATIC);

        await pool.connect(alice).withdraw(MATIC, BNB, amount, ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, false, { value: fees });
        let fee = await feeProvider.feeAmount(BNB,MATIC);
        expect((fee)).to.almost.equal(toTokenAmount(0));
        await expect(clientB.connect(bob).depositRequest(MATIC, toTokenAmount(1e3), LZO, 0, { value: fees }))
                    .to.emit(poolWithLibraryABI,"Deposit")
                    .withArgs(bob.address,MATIC,BNB,toTokenAmount(1e3),anyValue,LZO,captureAmount);
        
        //No reward on deposit 
        expect((capturedAmount)).to.almost.equal(toTokenAmount(0));

    });

    it("Reward distribution for deposit from fee taken", async function () {

        let amount = await feeProvider.getWithdrawAbleAmountWithoutFee(BNB,MATIC);

        // extra amount drawn in addition to incurr fee
        amount = toTokenAmount(parseFloat(toMathAmount(amount)) + 10000);
      
        await pool.connect(alice).withdraw(MATIC, BNB, amount, ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, false, { value: fees });
        let fee = await feeProvider.feeAmount(BNB,MATIC);
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(16.200836820083666);

        await expect(clientB.connect(bob).depositRequest(MATIC, toTokenAmount(1e3), LZO, 0, { value: fees }))
                    .to.emit(poolWithLibraryABI,"Deposit")
                    .withArgs(bob.address,MATIC,BNB,toTokenAmount(1e3),anyValue,LZO,captureAmount);
        
        //Reward on deposit 
        expect(parseFloat(toMathAmount(capturedAmount))).to.almost.equal(1.816237311668573);
        fee = await feeProvider.feeAmount(BNB,MATIC);
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(16.200836820083666 - 1.816237311668573 );

    });

    it("Linear Reward distribution for deposit/repay ", async function () {
        let amount = await feeProvider.getWithdrawAbleAmountWithoutFee(BNB,MATIC);

        // extra amount drawn in addition to incurr fee
        amount = toTokenAmount(parseFloat(toMathAmount(amount)) + 20000);
        
        
        await pool.connect(alice).withdraw(MATIC, BNB, amount, ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, false, { value: fees });

        let fee = await feeProvider.feeAmount(BNB,MATIC);
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(67.92982456140348);
                
        let reward = await feeProvider.getRewardAmount(BNB,MATIC,toTokenAmount(1));
        expect(parseFloat(toMathAmount(reward))).to.almost.equal(0.0038596228071969677);
        reward = await feeProvider.getRewardAmount(BNB,MATIC,toTokenAmount(10));
        expect(parseFloat(toMathAmount(reward))).to.almost.equal(0.03859385982853641);
        reward = await feeProvider.getRewardAmount(BNB,MATIC,toTokenAmount(100));
        expect(parseFloat(toMathAmount(reward))).to.almost.equal(0.3857019336895497);
        reward = await feeProvider.getRewardAmount(BNB,MATIC,toTokenAmount(1000));
        expect(parseFloat(toMathAmount(reward))).to.almost.equal(3.833511544097263);
        reward = await feeProvider.getRewardAmount(BNB,MATIC,toTokenAmount(10000));
        expect(parseFloat(toMathAmount(reward))).to.almost.equal(36.13288540500186);

        //Max Fee after liquidity crosses 60% of optimal balance after deposit
        reward = await feeProvider.getRewardAmount(BNB,MATIC,toTokenAmount(20000));
        expect(parseFloat(toMathAmount(reward))).to.almost.equal(67.92982456140348);

        reward = await feeProvider.getRewardAmount(BNB,MATIC,toTokenAmount(25000));
        expect(parseFloat(toMathAmount(reward))).to.almost.equal(67.92982456140348);

        await expect(clientB.connect(alice).depositRequest(MATIC, toTokenAmount(25000), LZO, 0, { value: fees }))
        .to.emit(poolWithLibraryABI,"Deposit")
        .withArgs(alice.address,MATIC,BNB,toTokenAmount(25000),anyValue,LZO,captureAmount);

        expect(parseFloat(toMathAmount(capturedAmount))).to.almost.equal(67.92982456140348);

        // all fee incurred given as reward
        fee = await feeProvider.feeAmount(BNB,MATIC);
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(0);

    });

    it(" Fee distribution for withdraw/borrow ", async function () {   
        let fee = await feeProvider.getFeeAmount(BNB,MATIC,toTokenAmount(10000));
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(0);
        fee = await feeProvider.getFeeAmount(BNB,MATIC,toTokenAmount(50000));
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(0);
        fee = await feeProvider.getFeeAmount(BNB,MATIC,toTokenAmount(72727));
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(0);

        // when liquidity on chain drops below 60% of optimal balance, fee is charged
        fee = await feeProvider.getFeeAmount(BNB,MATIC,toTokenAmount(80000));
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(8.462809917355372);
        fee = await feeProvider.getFeeAmount(BNB,MATIC,toTokenAmount(90000));
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(50.00865800865801);
        fee = await feeProvider.getFeeAmount(BNB,MATIC,toTokenAmount(97000));
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(102.16068069861174);
        fee = await feeProvider.getFeeAmount(BNB,MATIC,toTokenAmount(98000));
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(111.39801980198021);

        // when liquidity on chain drops below 5% of optimal balance, fee rises sharply
        fee = await feeProvider.getFeeAmount(BNB,MATIC,toTokenAmount(98500));
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(181.12952853598017);
        fee = await feeProvider.getFeeAmount(BNB,MATIC,toTokenAmount(99000));
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(371.86865671641795);
        fee = await feeProvider.getFeeAmount(BNB,MATIC,toTokenAmount(99500));
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(684.5206982543641);

        //max fee for withdrawing all liquidity
        fee = await feeProvider.getFeeAmount(BNB,MATIC,toTokenAmount(100000));
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(1120.0);

    });

    it(" Fee check for borrow ", async function () {   
        let fee = await feeProvider.getFeeAmount(BNB,MATIC,toTokenAmount(70000));
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(0);
   
        fee = await feeProvider.getFeeAmount(BNB,MATIC,toTokenAmount(80000));
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(8.462809917355372);

        await expect(pool.connect(bob).borrow(MATIC, BNB, toTokenAmount(70000), ethers.utils.hexZeroPad(bob.address, 32), LZO, 0, { value: fees }))
                    .to.emit(poolWithLibraryABI,"Borrow")
                    .withArgs(bob.address,bob.address,MATIC,BNB,toTokenAmount(70000),anyValue,LZO,captureAmount);
        
        expect((capturedAmount)).to.almost.equal(toTokenAmount(0));

        await expect(pool.connect(bob).borrow(MATIC, BNB, toTokenAmount(10000), ethers.utils.hexZeroPad(bob.address, 32), LZO, 0, { value: fees }))
                    .to.emit(poolWithLibraryABI,"Borrow")
                    .withArgs(bob.address,bob.address,MATIC,BNB,anyValue,anyValue,LZO,captureAmount);
        
        expect(parseFloat(toMathAmount(capturedAmount))).to.almost.equal(8.462809917355372);

        await expect(pool.connect(bob).borrow(MATIC, BNB, toTokenAmount(10000), ethers.utils.hexZeroPad(bob.address, 32), LZO, 0, { value: fees }))
                    .to.emit(poolWithLibraryABI,"Borrow")
                    .withArgs(bob.address,bob.address,MATIC,BNB,anyValue,anyValue,LZO,captureAmount);
        
        expect(parseFloat(toMathAmount(capturedAmount))).to.almost.equal(44.15584415584416);

    });

    it.only(" Reward check for repay ", async function () {   

        await pool.connect(bob).borrow(MATIC, BNB, toTokenAmount(90000), ethers.utils.hexZeroPad(bob.address, 32), LZO, 0, { value: fees });
        let fee = await feeProvider.feeAmount(BNB,MATIC);
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(50.00865800865801);

        await expect(clientB.connect(bob).repayRequest(MATIC, toTokenAmount(10000), LZO, 0, { value: fees }))
        .to.emit(poolWithLibraryABI,"Repay")
        .withArgs(bob.address,MATIC,BNB,anyValue,anyValue,anyValue,LZO,captureAmount);

        expect(parseFloat(toMathAmount(capturedAmount))).to.almost.equal(30.493084151620735);

        fee = await feeProvider.feeAmount(BNB,MATIC);
        expect(parseFloat(toMathAmount(fee))).to.almost.equal(50.00865800865801 - 30.493084151620735 );

        reward = await feeProvider.getRewardAmount(BNB,MATIC,toTokenAmount(10000));
        expect(parseFloat(toMathAmount(reward))).to.almost.equal(19.515573857037275);

        await expect(clientB.connect(bob).repayRequest(MATIC, toTokenAmount(10000), LZO, 0, { value: fees }))
        .to.emit(poolWithLibraryABI,"Repay")
        .withArgs(bob.address,MATIC,BNB,anyValue,anyValue,anyValue,LZO,captureAmount);

        expect(parseFloat(toMathAmount(capturedAmount))).to.almost.equal(19.515573857037275);
        let coreWithLibraryABI = await ethers.getContractAt("Data", core.address);
        await expect(clientB.connect(bob).repayRequest(MATIC, toTokenAmount(10000), LZO, 0, { value: fees }))
        .to.emit(coreWithLibraryABI,"InterestRateUpdated")
        .withArgs(anyValue,captureAmount);

        // expect(parseFloat(toMathAmount(capturedAmount))).to.almost.equal(0);
        // let b = await core.pools(MATIC);
        console.log(capturedAmount);

    });
})
