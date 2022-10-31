const { expect } = require("chai")
const { ethers } = require("hardhat")

let BN = require("bignumber.js");

const toTokenAmount = (amount, decimals = 18) => {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();

const MATIC = ethers.utils.formatBytes32String("MATIC");
const FTM = ethers.utils.formatBytes32String("FTM");

describe("Ready", function () {

    beforeEach(async function () {
        [developer, alice, bob] = await ethers.getSigners()

        // use this chainId
        this.chainIdServer = 1
        this.chainIdClientA = 2
        this.chainIdClientB = 3

        // create a LayerZero Endpoint mock for testing
        const LayerZeroEndpointMock = await ethers.getContractFactory("LZEndpointMock")
        this.lzEndpointMockServer = await LayerZeroEndpointMock.deploy(this.chainIdServer)
        this.lzEndpointMockClientA = await LayerZeroEndpointMock.deploy(this.chainIdClientA)
        this.lzEndpointMockClientB = await LayerZeroEndpointMock.deploy(this.chainIdClientB)

        this.lzEndpointMockServer.setEstimatedFees(toTokenAmount(0.001), 0);
        this.lzEndpointMockClientA.setEstimatedFees(toTokenAmount(0.001), 0);
        this.lzEndpointMockClientB.setEstimatedFees(toTokenAmount(0.001), 0);

        const CEToken = await ethers.getContractFactory("CEToken");
        this.ceMATIC = await CEToken.deploy("CEMATIC", "CEMATIC");
        this.ceFTM = await CEToken.deploy("CEFTM", "CEFTM");

        const DebtToken = await ethers.getContractFactory("DebtToken");
        this.debtMATIC = await DebtToken.deploy("DebtMATIC", "DebtMATIC");
        this.debtFTM = await DebtToken.deploy("DebtFTM", "DebtFTM");

        const ERC20 = await ethers.getContractFactory("ERC20Mock")
        this.matic = await ERC20.deploy("MATIC", "MATIC")
        this.ftm = await ERC20.deploy("FTM", "FTM")

        const Oracle = await ethers.getContractFactory("Oracle");
        this.oracle = await Oracle.deploy();

        const Client = await ethers.getContractFactory("Client")
        this.clientA = await Client.deploy(this.lzEndpointMockClientA.address, this.chainIdServer)
        this.clientB = await Client.deploy(this.lzEndpointMockClientB.address, this.chainIdServer)

        const Server = await ethers.getContractFactory("Pool")
        this.server = await Server.deploy(this.lzEndpointMockServer.address)

        await this.server.setOracle(this.oracle.address);
        await this.oracle.setPrice([MATIC, FTM], [toTokenAmount(1), toTokenAmount(0.1)])

        await this.server.initPool(MATIC, [toTokenAmount(0.5), toTokenAmount(0.04), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.8), toTokenAmount(0.1)], this.ceMATIC.address, this.debtMATIC.address);
        await this.server.initPool(FTM, [toTokenAmount(0.5), toTokenAmount(0.04), toTokenAmount(0.5), 0, toTokenAmount(0.5), toTokenAmount(0.8), toTokenAmount(0.1)], this.ceFTM.address, this.debtFTM.address);
        await this.server.changePoolStatus(MATIC, true);
        await this.server.changePoolStatus(FTM, true);

        await this.lzEndpointMockServer.setDestLzEndpoint(this.clientA.address, this.lzEndpointMockClientA.address)
        await this.lzEndpointMockServer.setDestLzEndpoint(this.clientB.address, this.lzEndpointMockClientB.address)

        await this.lzEndpointMockClientA.setDestLzEndpoint(this.server.address, this.lzEndpointMockServer.address)
        await this.lzEndpointMockClientB.setDestLzEndpoint(this.server.address, this.lzEndpointMockServer.address)

        // set each contracts source address so it can send to each other
        await this.clientA.setTrustedRemote(this.chainIdServer, this.server.address)
        await this.clientB.setTrustedRemote(this.chainIdServer, this.server.address)

        await this.server.setTrustedRemote(this.chainIdClientA, this.clientA.address)
        await this.server.setTrustedRemote(this.chainIdClientB, this.clientB.address)

        await this.matic.mint(alice.address, toTokenAmount(1e6))
        await this.ftm.mint(alice.address, toTokenAmount(1e6))
        await this.matic.mint(bob.address, toTokenAmount(1e6))
        await this.ftm.mint(bob.address, toTokenAmount(1e6))

        await this.matic.connect(alice).approve(this.clientA.address, toTokenAmount(1e6));
        await this.matic.connect(bob).approve(this.clientA.address, toTokenAmount(1e6));
        await this.ftm.connect(alice).approve(this.clientB.address, toTokenAmount(1e6));
        await this.ftm.connect(bob).approve(this.clientB.address, toTokenAmount(1e6));

        await this.clientA.setPool(MATIC, this.matic.address, true);
        await this.clientB.setPool(FTM, this.ftm.address, true);
    })

    it("Simple test", async function () {
        let fees = await this.clientA.connect(alice).estimateFees(1);
        console.log(fees);
        await this.clientA.connect(alice).depositRequest(MATIC, toTokenAmount(500000), {value: fees})
        // let shareA = (await this.server.userInfos(alice.address, 1))["shareA"];
        // console.log(toMathAmount(shareA));

        // await this.clientB.connect(bob).depositRequest(1, toTokenAmount(5e5), {value: fees})
        // let shareB = (await this.server.userInfos(bob.address, 1))["shareB"];
        // console.log(toMathAmount(shareB));

        // fees = await this.clientA.connect(alice).estimateFees(2);
        // // console.log(fees);
        // await this.clientB.connect(alice).borrowRequest(1, toTokenAmount(1e5), {value: fees});
        // expect(await this.bnb.balanceOf(alice.address)).to.be.equal(toTokenAmount(1100000))

        // await this.clientA.connect(alice).withdrawRequest(1, toTokenAmount(1e5), {value: fees})
        // expect(await this.matic.balanceOf(alice.address)).to.be.equal(toTokenAmount(6e5))

        // await network.provider.send("evm_increaseTime", [3600 * 1000])

        // await expect(this.clientA.connect(alice).withdrawRequest(1, toTokenAmount(200001), {value: fees})).to.be.revertedWith("Health check failed");
        // await this.clientB.connect(alice).repayRequest(1, toTokenAmount(50000), {value: fees})
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
