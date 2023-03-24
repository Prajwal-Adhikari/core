const { expect } = require("chai")
const { ethers } = require("hardhat")

let BN = require("bignumber.js");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();

const MATIC = ethers.utils.formatBytes32String("MATIC");
const FTM = ethers.utils.formatBytes32String("FTM");
const BNB = ethers.utils.formatBytes32String("BNB");
let server, treasury, matic, ftm, bnb
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

        const Oracle = await ethers.getContractFactory("Oracle");
        this.oracle = await Oracle.deploy();

        const Client = await ethers.getContractFactory("Branch")
        this.clientA = await Client.deploy(this.lzEndpointMockClientA.address, this.chainIdClientA, this.chainIdServer)
        this.clientB = await Client.deploy(this.lzEndpointMockClientB.address, this.chainIdClientB, this.chainIdServer)
        this.clientC = await Client.deploy(this.lzEndpointMockClientC.address, this.chainIdClientC, this.chainIdServer)

        const Server = await ethers.getContractFactory("Pool")
        server = await Server.deploy(this.lzEndpointMockServer.address, treasury.address, this.chainIdServer);

        await this.ceMATIC.initialize(server.address);
        await this.ceFTM.initialize(server.address);
        await this.ceBNB.initialize(server.address);
        await this.debtMATIC.initialize(server.address);
        await this.debtFTM.initialize(server.address);
        await this.debtBNB.initialize(server.address);

        await server.setOracle(this.oracle.address);
        await this.oracle.setPrice([MATIC, FTM, BNB], [toTokenAmount(1), toTokenAmount(1), toTokenAmount(1)])

        await server.initPool(MATIC, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.05)], this.ceMATIC.address, this.debtMATIC.address);
        await server.initPool(FTM, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.05)], this.ceFTM.address, this.debtFTM.address);
        await server.initPool(BNB, [toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.5), toTokenAmount(0.1), toTokenAmount(0.05)], this.ceBNB.address, this.debtBNB.address);
        await server.changePoolStatus(MATIC, true);
        await server.changePoolStatus(FTM, true);
        await server.changePoolStatus(BNB, true);

        await this.lzEndpointMockServer.setDestLzEndpoint(this.clientA.address, this.lzEndpointMockClientA.address)
        await this.lzEndpointMockServer.setDestLzEndpoint(this.clientB.address, this.lzEndpointMockClientB.address)

        await this.lzEndpointMockClientA.setDestLzEndpoint(server.address, this.lzEndpointMockServer.address)
        await this.lzEndpointMockClientB.setDestLzEndpoint(server.address, this.lzEndpointMockServer.address)

        // set each contracts source address so it can send to each other
        await this.clientA.setTrustedRemote(this.chainIdServer, getAddress(this.clientA.address, server.address))
        await this.clientB.setTrustedRemote(this.chainIdServer, getAddress(this.clientB.address, server.address))
        await this.clientC.setTrustedRemote(this.chainIdServer, getAddress(this.clientC.address, server.address))

        await server.setTrustedRemote(this.chainIdClientA, getAddress(server.address, this.clientA.address))
        await server.setTrustedRemote(this.chainIdClientB, getAddress(server.address, this.clientB.address))
        await server.setTrustedRemote(this.chainIdClientC, getAddress(server.address, this.clientC.address))

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
    })

    async function printInfo() {
        let matic_reserve = await server.reserves(MATIC);
        console.log("MATIC");
        console.log(`interest rate: ${matic_reserve[0]} currentRatio: ${matic_reserve[1]} ceScaled: ${matic_reserve[4]}`)
        console.log(`dtScaled: ${matic_reserve[5]} ceSupply: ${matic_reserve[7]} debtSupply: ${matic_reserve[8]}`)

        let ftm_reserve = await server.reserves(FTM);
        console.log("FTM");
        console.log(`interest rate: ${ftm_reserve[0]} currentRatio: ${ftm_reserve[1]} ceScaled: ${ftm_reserve[4]}`)
        console.log(`dtScaled: ${ftm_reserve[5]} ceSupply: ${ftm_reserve[7]} debtSupply: ${ftm_reserve[8]}`)

        let bnb_reserve = await server.reserves(BNB);
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

        let factor = await server.healthFactor(alice.address);
        console.log(`alice health factor collateral:${factor[0]} debt:${factor[1]} factor:${factor[2]} lts:${factor[3]}`)
        factor = await server.healthFactor(bob.address);
        console.log(`bob health factor collateral:${factor[0]} debt:${factor[1]} factor:${factor[2]} lts:${factor[3]}`)
    }

    it("Simple test", async function () {
        let fees = await this.clientA.connect(alice).estimateFees(1);
        console.log(fees);

        console.log("alice deposit matic");
        await this.clientA.connect(alice).depositRequest(MATIC, toTokenAmount(500000), {value: fees})
        await printInfo();

        console.log("bob deposit ftm");
        await this.clientB.connect(bob).depositRequest(FTM, toTokenAmount(5e5), {value: fees})
        await printInfo();

        console.log("alice deposit bnb");
        await this.clientC.connect(alice).depositRequest(BNB, toTokenAmount(500000), {value: fees})
        await printInfo();

        console.log("alice borrow ftm and after one month");
        await server.connect(alice).borrow(FTM, this.chainIdClientB, toTokenAmount(1e5), ethers.utils.hexZeroPad(alice.address, 32), {value: fees});
        await network.provider.send("evm_increaseTime", [365 * 86400 - 1])
        await printInfo();

        console.log("alice withdraw matic");
        await server.connect(alice).withdraw(MATIC, this.chainIdClientA, toTokenAmount(1e5), ethers.utils.hexZeroPad(alice.address, 32), {value: fees})
        await printInfo();

        console.log("bob withdraw ftm");
        await server.connect(bob).withdraw(FTM, this.chainIdClientB, toTokenAmount(1e5), ethers.utils.hexZeroPad(bob.address, 32), {value: fees})
        await printInfo();

        console.log("alice withdraw bnb");
        await server.connect(alice).withdraw(BNB, this.chainIdClientC, toTokenAmount(1e5), ethers.utils.hexZeroPad(alice.address, 32), {value: fees})
        await printInfo();

        console.log("alice withdraw matic")
        await server.connect(alice).withdraw(MATIC, this.chainIdClientA, toTokenAmount(180000), ethers.utils.hexZeroPad(alice.address, 32), {value: fees})
        await printInfo();
        // expect(await matic.balanceOf(alice.address)).to.be.equal(toTokenAmount(6e5))

        await network.provider.send("evm_increaseTime", [365 * 86400])
        console.log("alice repay ftm")
        // await expect(server.connect(alice).withdraw(MATIC, this.chainIdClientA, toTokenAmount(263550), {value: fees})).to.be.revertedWith("Health check failed");
        await this.clientB.connect(alice).repayRequest(FTM, toTokenAmount(50000), {value: fees})
        await printInfo();

        await this.clientB.connect(alice).repayRequest(FTM, toTokenAmount(200000), {value: fees})
        await printInfo();


        console.log("alice deposit matic");
        await this.clientA.connect(alice).depositRequest(MATIC, toTokenAmount(500000), {value: fees})
        await printInfo();

        console.log("bob borrow matic");
        await server.connect(bob).borrow(MATIC, this.chainIdClientA, toTokenAmount(2e5), ethers.utils.hexZeroPad(bob.address, 32), {value: fees});
        await network.provider.send("evm_increaseTime", [365 * 86400 - 1])
        await printInfo();
        // let borrowB = (await this.server.userInfos(alice.address, 1))["borrowedB"]; 
        // let interestB = (await this.server.userInfos(alice.address, 1))["interestB"];
        // console.log(toMathAmount(borrowB), toMathAmount(interestB)) 

        // console.log(toMathAmount(await this.bnb.balanceOf(alice.address)))

        // console.log(toMathAmount(await this.bnb.balanceOf(bob.address)))
        // await this.clientB.connect(bob).withdrawRequest(1, toTokenAmount(1e4), {value: fees})
        // console.log(toMathAmount(await this.bnb.balanceOf(bob.address)))

        // shareB = (await this.server.userInfos(bob.address, 1))["shareB"];
        // console.log(toMathAmount(shareB));
    })
})
