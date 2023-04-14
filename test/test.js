const { expect } = require("chai")
const { ethers, upgrades } = require("hardhat")

let BN = require("bignumber.js");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();

const MATIC = ethers.utils.formatBytes32String("MATIC");
const FTM = ethers.utils.formatBytes32String("FTM");
const BNB = ethers.utils.formatBytes32String("BNB");
const LZO = ethers.utils.formatBytes32String("LZO");
let server, core, liquidationManager, treasury, matic, ftm, bnb;
function getAddress(b, a) {
  return ethers.utils.solidityPack(['address','address'],
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
        this.ceMATIC = await CEToken.deploy("CEMATIC", "CEMATIC");
        this.ceFTM = await CEToken.deploy("CEFTM", "CEFTM");    
        this.ceBNB = await CEToken.deploy("CEBNB", "CEBNB");

        const DebtToken = await ethers.getContractFactory("DebtToken");
        this.debtMATIC = await DebtToken.deploy("DebtMATIC", "DebtMATIC");
        this.debtFTM = await DebtToken.deploy("DebtFTM", "DebtFTM");
        this.debtBNB = await DebtToken.deploy("DebtBNB", "DebtBNB");

        const ERC20 = await ethers.getContractFactory("ERC20Mock")
        matic = await ERC20.deploy("MATIC", "MATIC")
        ftm = await ERC20.deploy("FTM", "FTM")
        bnb = await ERC20.deploy("BNB", "BNB")

        const Cedro = await ethers.getContractFactory("CedroToken");
        this.cedro = await Cedro.deploy(toTokenAmount(1e9));

        const FeeProvider = await ethers.getContractFactory("FeeProvider");
        this.feeProvider = await upgrades.deployProxy(FeeProvider, []);

        const Oracle = await ethers.getContractFactory("Oracle");
        this.oracle = await Oracle.deploy();

        const Client = await ethers.getContractFactory("Branch");
        this.clientA = await upgrades.deployProxy(Client, []);
        this.clientB = await upgrades.deployProxy(Client, []);
        this.clientC = await upgrades.deployProxy(Client, []);

        // Client Adapter
        const Adapter = await ethers.getContractFactory("AdapterBranch");
        this.adapterA = await upgrades.deployProxy(Adapter, []);
        await this.adapterA.setBranch(this.clientA.address);
        this.adapterB = await upgrades.deployProxy(Adapter, []);
        await this.adapterB.setBranch(this.clientB.address);
        this.adapterC = await upgrades.deployProxy(Adapter, []);
        await this.adapterC.setBranch(this.clientC.address);

        // Client Route
        const Route = await ethers.getContractFactory("LzRouteBranch");
        this.routeA = await upgrades.deployProxy(Route, [this.lzEndpointMockClientA.address, this.chainIdClientA, this.chainIdServer]);
        await this.routeA.setAdapter(this.adapterA.address);
        this.routeB = await upgrades.deployProxy(Route, [this.lzEndpointMockClientB.address, this.chainIdClientB, this.chainIdServer]);
        await this.routeB.setAdapter(this.adapterB.address);
        this.routeC = await upgrades.deployProxy(Route, [this.lzEndpointMockClientC.address, this.chainIdClientC, this.chainIdServer]);
        await this.routeC.setAdapter(this.adapterC.address);

        // Configure Route in Adapter
        await this.adapterA.setRoute(LZO, this.routeA.address);
        await this.adapterB.setRoute(LZO, this.routeB.address);
        await this.adapterC.setRoute(LZO, this.routeC.address);

        // Configure Adapter in Client
        await this.clientA.setAdapter(this.adapterA.address);
        await this.clientB.setAdapter(this.adapterB.address);
        await this.clientC.setAdapter(this.adapterC.address);

        

        const Server = await ethers.getContractFactory("Pool");
        server =  await upgrades.deployProxy(Server, []);

        // Server Adapter
        const AdapterPool = await ethers.getContractFactory("AdapterPool");
        this.adapterS = await upgrades.deployProxy(AdapterPool, []);
        await this.adapterS.setPool(server.address);

        // Server Route
        const LzRoutePool = await ethers.getContractFactory("LzRoutePool");
        this.routeS = await upgrades.deployProxy(LzRoutePool, [this.lzEndpointMockServer.address, this.chainIdServer]);
        await this.routeS.setAdapter(this.adapterS.address);
        await this.routeS.setChainNameID(MATIC, this.chainIdServer);
        await this.routeS.setChainNameID(FTM, this.chainIdClientA);
        await this.routeS.setChainNameID(BNB, this.chainIdClientB);

        // Configure Route in Adapter
        await this.adapterS.setRoute(LZO, this.routeS.address);

        // Configure Adapter in Server
        await server.setAdapter(this.adapterS.address);

        const Core = await ethers.getContractFactory("Core");
        core =  await upgrades.deployProxy(Core, [treasury.address]);

        const LiquidationManager = await ethers.getContractFactory("LiquidationManager");
        liquidationManager =  await upgrades.deployProxy(LiquidationManager, []);

        

        await this.ceMATIC.initialize(core.address, liquidationManager.address);
        await this.ceFTM.initialize(core.address, liquidationManager.address);
        await this.ceBNB.initialize(core.address, liquidationManager.address);
        await this.debtMATIC.initialize(core.address, liquidationManager.address);
        await this.debtFTM.initialize(core.address, liquidationManager.address);
        await this.debtBNB.initialize(core.address, liquidationManager.address);

        await core.setOracle(this.oracle.address);
        await server.setCore(core.address);
        await core.setPool(server.address);
        await server.setCedroToken(this.cedro.address);
        await server.setFeeProvider(this.feeProvider.address);
        await this.feeProvider.setCore(core.address);
        await this.oracle.setPrice([MATIC, FTM, BNB], [toTokenAmount(1), toTokenAmount(1), toTokenAmount(1)])
        await liquidationManager.setOracle(this.oracle.address);
        await liquidationManager.setCore(core.address);

        await core.initPool(MATIC, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.05), toTokenAmount(0.05)], this.ceMATIC.address, this.debtMATIC.address);
        await core.initPool(FTM, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.05), toTokenAmount(0.05)], this.ceFTM.address, this.debtFTM.address);
        await core.initPool(BNB, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.05), toTokenAmount(0.05)], this.ceBNB.address, this.debtBNB.address);
        await core.changePoolStatus(MATIC, true);
        await core.changePoolStatus(FTM, true);
        await core.changePoolStatus(BNB, true);

        await this.lzEndpointMockServer.setDestLzEndpoint(this.routeA.address, this.lzEndpointMockClientA.address)
        await this.lzEndpointMockServer.setDestLzEndpoint(this.routeB.address, this.lzEndpointMockClientB.address)

        await this.lzEndpointMockClientA.setDestLzEndpoint(this.routeS.address, this.lzEndpointMockServer.address)
        await this.lzEndpointMockClientB.setDestLzEndpoint(this.routeS.address, this.lzEndpointMockServer.address)
        // set each contracts source address so it can send to each other
        await this.routeA.setTrustedRemote(this.chainIdServer, getAddress(this.routeA.address, this.routeS.address))
        await this.routeB.setTrustedRemote(this.chainIdServer, getAddress(this.routeB.address, this.routeS.address))
        await this.routeC.setTrustedRemote(this.chainIdServer, getAddress(this.routeC.address, this.routeS.address))

        await this.routeS.setTrustedRemote(this.chainIdClientA, getAddress(this.routeS.address, this.routeA.address))
        await this.routeS.setTrustedRemote(this.chainIdClientB, getAddress(this.routeS.address, this.routeB.address))
        await this.routeS.setTrustedRemote(this.chainIdClientC, getAddress(this.routeS.address, this.routeC.address))

        await matic.mint(alice.address, toTokenAmount(1e6))
        await ftm.mint(alice.address, toTokenAmount(1e6))
        await bnb.mint(alice.address, toTokenAmount(1e6))
        await matic.mint(bob.address, toTokenAmount(1e6))
        await ftm.mint(bob.address, toTokenAmount(1e6))
        await bnb.mint(bob.address, toTokenAmount(1e6))

        await matic.connect(alice).approve(this.clientA.address, toTokenAmount(1e6));
        await matic.connect(bob).approve(this.clientA.address, toTokenAmount(1e6));
        await ftm.connect(alice).approve(this.clientB.address, toTokenAmount(1e6));
        await ftm.connect(bob).approve(this.clientB.address, toTokenAmount(1e6));
        await bnb.connect(alice).approve(this.clientC.address, toTokenAmount(1e6));
        await bnb.connect(bob).approve(this.clientC.address, toTokenAmount(1e6));

        await this.clientA.setPool(MATIC, matic.address, true);
        await this.clientB.setPool(FTM, ftm.address, true);
        await this.clientC.setPool(BNB, bnb.address, true);
        console.log("finish")
    })

    async function printInfo() {
        let matic_reserve = await core.reserves(MATIC);
        console.log(core.address);
        console.log(MATIC);
        console.log(matic_reserve);
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
        let fees = await this.routeA.connect(alice).estimateFees(1);
        console.log(fees);

        console.log("alice deposit matic");
        (await this.clientA.connect(alice).depositRequest(MATIC, toTokenAmount(500000), LZO, {value: fees})).wait()
        await printInfo();

        console.log("bob deposit ftm");
        await this.clientB.connect(bob).depositRequest(FTM, toTokenAmount(5e5), LZO, {value: fees})
        await printInfo();

        console.log("alice deposit bnb");
        await this.clientC.connect(alice).depositRequest(BNB, toTokenAmount(500000), LZO, {value: fees})
        await printInfo();

        console.log("alice borrow ftm and after one month");
        await server.connect(alice).borrow(FTM, BNB, toTokenAmount(1e5), ethers.utils.hexZeroPad(alice.address, 32), LZO, {value: fees});
        await network.provider.send("evm_increaseTime", [365 * 86400 - 1])
        await printInfo();

        console.log("alice withdraw matic");
        await server.connect(alice).withdraw(MATIC, FTM, toTokenAmount(1e5), ethers.utils.hexZeroPad(alice.address, 32), {value: fees})
        await printInfo();

        console.log("bob withdraw ftm");
        await server.connect(bob).withdraw(FTM, BNB, toTokenAmount(1e5), ethers.utils.hexZeroPad(bob.address, 32), {value: fees})
        await printInfo();

        console.log("alice withdraw bnb");
        await server.connect(alice).withdraw(BNB, MATIC, toTokenAmount(1e5), ethers.utils.hexZeroPad(alice.address, 32), {value: fees})
        await printInfo();

        console.log("alice withdraw matic")
        await server.connect(alice).withdraw(MATIC, FTM, toTokenAmount(180000), ethers.utils.hexZeroPad(alice.address, 32), {value: fees})
        await printInfo();
        // expect(await matic.balanceOf(alice.address)).to.be.equal(toTokenAmount(6e5))

        await network.provider.send("evm_increaseTime", [365 * 86400])
        console.log("alice repay ftm")
        // await expect(server.connect(alice).withdraw(MATIC, FTM, toTokenAmount(263550), {value: fees})).to.be.revertedWith("Health check failed");
        await this.clientB.connect(alice).repayRequest(FTM, toTokenAmount(50000), {value: fees})
        await printInfo();

        await this.clientB.connect(alice).repayRequest(FTM, toTokenAmount(200000), {value: fees})
        await printInfo();


        console.log("alice deposit matic");
        await this.clientA.connect(alice).depositRequest(MATIC, toTokenAmount(500000), {value: fees})
        await printInfo();

        console.log("bob borrow matic");
        await server.connect(bob).borrow(MATIC, this.FTM, toTokenAmount(2e5), ethers.utils.hexZeroPad(bob.address, 32), {value: fees});
        await network.provider.send("evm_increaseTime", [365 * 86400 - 1])
        await printInfo();

        console.log("liquidate test");
        await liquidationManager.connect(alice).liquidate(bob.address, FTM, MATIC, toTokenAmount(100000));
        await printInfo();
    })

    // it("Test reward", async function () {
    //     let fees = await this.routeA.connect(alice).estimateFees(MATIC);

    //     await server.setFeeRewardStatus(true, true);

    //     await this.cedro.transfer(server.address, toTokenAmount(500000));

    //     let balance_matic_client = await matic.balanceOf(this.clientA.address);
    //     console.log("Before balance of matic pool", balance_matic_client.toString(), this.clientA.address);

    //     await this.clientA.connect(alice).depositRequest(MATIC, toTokenAmount(500000), {value: fees});
        
    //     console.log("Alice gets cedro reward");
    //     let balance = await this.cedro.balanceOf(alice.address);
    //     console.log("reward", balance.toString(), alice.address);
    //     // expect(balance).to.equal(toTokenAmount(1));

    //     balance = await this.cedro.balanceOf(server.address);
    //     console.log("remaining balance", balance.toString(), server.address);
    
    //     await printInfo();

    //     balance_matic_client = await matic.balanceOf(this.clientA.address);
    //     console.log("After balance of matic pool", balance_matic_client.toString(), this.clientA.address);

    //     balance = await this.ceMATIC.balanceOf(alice.address);
    //     console.log("CEtoken", balance.toString(), alice.address);
    //     // expect(balance).to.equal(toTokenAmount(500000));

    // })
})
