const { expect } = require("chai")
const { ethers, upgrades } = require("hardhat")

let BN = require("bignumber.js");
const { keccak256 } = require("ethers/lib/utils");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();

const MATIC = ethers.utils.formatBytes32String("MATIC");
const FTM = ethers.utils.formatBytes32String("FTM");
const BNB = ethers.utils.formatBytes32String("BNB");
const LZO = ethers.utils.formatBytes32String("LZO");

// Contracts
let pool, core, liquidationManager, treasury, feeProvider, controller;
let clientA, clientB, clientC, adapterA, adapterB, adapterC, adapterS, routeA, routeB, routeC, routeS;
let roleManagerS, roleManagerA, roleManagerB, roleManagerC;
let matic, ftm, bnb, ceFTM, ceBNB, ceMATIC, debtFTM, debtBNB, debtMATIC;


function getAddress(b, a) {
    return ethers.utils.solidityPack(['address', 'address'],
        [a, b]);
}
describe("Ready", function () {

    beforeEach(async function () {
        [developer, alice, bob, treasury] = await ethers.getSigners()


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

        const CEToken = await ethers.getContractFactory("CEToken");
        ceMATIC = await CEToken.deploy("CEMATIC", "CEMATIC");
        ceFTM = await CEToken.deploy("CEFTM", "CEFTM");
        ceBNB = await CEToken.deploy("CEBNB", "CEBNB");

        const DebtToken = await ethers.getContractFactory("DebtToken");
        debtMATIC = await DebtToken.deploy("DebtMATIC", "DebtMATIC");
        debtFTM = await DebtToken.deploy("DebtFTM", "DebtFTM");
        debtBNB = await DebtToken.deploy("DebtBNB", "DebtBNB");

        const ERC20 = await ethers.getContractFactory("ERC20Mock")
        matic = await ERC20.deploy("MATIC", "MATIC")
        ftm = await ERC20.deploy("FTM", "FTM")
        bnb = await ERC20.deploy("BNB", "BNB")


        const FeeProvider = await ethers.getContractFactory("FeeProvider");
        feeProvider = await upgrades.deployProxy(FeeProvider, []);

        const Oracle = await ethers.getContractFactory("Oracle");
        this.oracle = await Oracle.deploy();

        const Client = await ethers.getContractFactory("Branch");
        clientA = await upgrades.deployProxy(Client, []);
        clientB = await upgrades.deployProxy(Client, []);
        clientC = await upgrades.deployProxy(Client, []);

        // Client Adapter
        const Adapter = await ethers.getContractFactory("AdapterBranch");
        adapterA = await upgrades.deployProxy(Adapter, []);
        adapterB = await upgrades.deployProxy(Adapter, []);
        adapterC = await upgrades.deployProxy(Adapter, []);

        // Client Route 400000 gas for testing
        const Route = await ethers.getContractFactory("LzRouteBranch");
        routeA = await upgrades.deployProxy(Route, [this.lzEndpointMockClientA.address, this.chainIdClientA, this.chainIdServer, 400000]);
        routeB = await upgrades.deployProxy(Route, [this.lzEndpointMockClientB.address, this.chainIdClientB, this.chainIdServer, 400000]);
        routeC = await upgrades.deployProxy(Route, [this.lzEndpointMockClientC.address, this.chainIdClientC, this.chainIdServer, 400000]);

        const RoleManagerBranch = await ethers.getContractFactory("RoleManagerBranch");
        roleManagerA = await upgrades.deployProxy(RoleManagerBranch, []);
        roleManagerB = await upgrades.deployProxy(RoleManagerBranch, []);
        roleManagerC = await upgrades.deployProxy(RoleManagerBranch, []);

        const Server = await ethers.getContractFactory("Pool");
        pool = await upgrades.deployProxy(Server, []);

        // Server Adapter
        const AdapterPool = await ethers.getContractFactory("AdapterPool");
        adapterS = await upgrades.deployProxy(AdapterPool, []);

        const RoleManagerPool = await ethers.getContractFactory("RoleManagerPool");
        roleManagerS = await upgrades.deployProxy(RoleManagerPool, []);

        const Core = await ethers.getContractFactory("Core");
        core = await upgrades.deployProxy(Core, [treasury.address]);

        // Server Route
        const LzRoutePool = await ethers.getContractFactory("LzRoutePool");
        routeS = await upgrades.deployProxy(LzRoutePool, [this.lzEndpointMockServer.address, this.chainIdServer, 200000]);

        const LiquidationManager = await ethers.getContractFactory("LiquidationManager");
        liquidationManager = await upgrades.deployProxy(LiquidationManager, []);

        const Controller = await ethers.getContractFactory("Controller");
        controller = await Controller.deploy();

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


        await ceMATIC.setCore(core.address);
        await ceFTM.setCore(core.address);
        await ceBNB.setCore(core.address);

        await core.setOracle(this.oracle.address);
        await pool.setCore(core.address);
        await pool.setFeeProvider(feeProvider.address);
        await feeProvider.setCore(core.address);
        await this.oracle.setPrice([MATIC, FTM, BNB], [toTokenAmount(1), toTokenAmount(1), toTokenAmount(1)])
        await liquidationManager.setOracle(this.oracle.address);
        await liquidationManager.setCore(core.address);

        // alice account only has the permission to init pool
        await core.connect(alice).initPool(MATIC, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(1), toTokenAmount(0.15)], ceMATIC.address, debtMATIC.address);
        await core.connect(alice).initPool(FTM, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(1), toTokenAmount(0.15)], ceFTM.address, debtFTM.address);
        await core.connect(alice).initPool(BNB, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(1), toTokenAmount(0.15)], ceBNB.address, debtBNB.address);

        // bob account only has the permission to change pool status
        await core.connect(bob).changePoolStatus(MATIC, true);
        await core.connect(bob).changePoolStatus(FTM, true);
        await core.connect(bob).changePoolStatus(BNB, true);

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
        await matic.mint(bob.address, toTokenAmount(1e6))
        await ftm.mint(bob.address, toTokenAmount(1e6))
        await bnb.mint(bob.address, toTokenAmount(1e6))

        await matic.connect(alice).approve(clientA.address, toTokenAmount(1e6));
        await matic.connect(bob).approve(clientA.address, toTokenAmount(1e6));
        await ftm.connect(alice).approve(clientB.address, toTokenAmount(1e6));
        await ftm.connect(bob).approve(clientB.address, toTokenAmount(1e6));
        await bnb.connect(alice).approve(clientC.address, toTokenAmount(1e6));
        await bnb.connect(bob).approve(clientC.address, toTokenAmount(1e6));

        await clientA.setPool(MATIC, matic.address, true);
        await clientB.setPool(FTM, ftm.address, true);
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
        let matic_reserve = await core.reserves(MATIC);
        console.log("MATIC");
        console.log(`interest rate: ${matic_reserve[0]} currentRatio: ${matic_reserve[1]} ceScaled: ${matic_reserve[4]}`)
        console.log(`dtScaled: ${matic_reserve[5]} ceSupply: ${matic_reserve[7]} debtSupply: ${matic_reserve[8]}`)

        let ftm_reserve = await core.reserves(FTM);
        console.log("FTM");
        console.log(`interest rate: ${ftm_reserve[0]} currentRatio: ${ftm_reserve[1]} ceScaled: ${ftm_reserve[4]}`)
        console.log(`dtScaled: ${ftm_reserve[5]} ceSupply: ${ftm_reserve[7]} debtSupply: ${ftm_reserve[8]}`)

        let bnb_reserve = await core.reserves(BNB);
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

        console.log("alice deposit bnb");
        await clientC.connect(alice).depositRequest(BNB, toTokenAmount(500000), LZO, 0, { value: fees })
        await printInfo();


        console.log("alice borrow ftm and after one month");
        await pool.connect(alice).borrow(FTM, BNB, toTokenAmount(1e5), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees });
        await network.provider.send("evm_increaseTime", [365 * 86400 - 1])
        await printInfo();

        console.log("alice withdraw matic");
        await pool.connect(alice).withdraw(MATIC, FTM, toTokenAmount(1e5), ethers.utils.hexZeroPad(alice.address, 32), LZO, 0, { value: fees })
        await printInfo();

        console.log("bob withdraw ftm");
        await pool.connect(bob).withdraw(FTM, BNB, toTokenAmount(1e5), ethers.utils.hexZeroPad(bob.address, 32), LZO, 0, { value: fees })
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
})
