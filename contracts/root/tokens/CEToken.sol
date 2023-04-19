// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ICore.sol";

contract CEToken is ERC20, Ownable {
    address public core;
    address public liquidationManager;
    address public controller;
    uint public transferBlockWait;           //Amount of blocks to wait before user can transfer minted ceToken
    uint public lockupTriggerAmt;            //amount where lockup will kick in after cross-chain transfer
    mapping (address => uint) public transferBlockRelease;    //Block number

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
    }

    modifier onlyCoreAndLiquidation() {
        require(msg.sender == core || msg.sender == liquidationManager, "Permission denied");
        _;
    }

    modifier onlyController() {
        require(msg.sender == controller, "Permission denied");
        _;
    }

    function initialize(address _core, address _liquidationManager) external onlyOwner {
        core = _core;
        liquidationManager = _liquidationManager;
       
    }

    function setController(address _controller) external onlyOwner {
        controller = _controller;
    }

    function setTransferBlockWait(uint num) external onlyOwner {
        transferBlockWait = num;
    }

    function setTransferBlockRelease(address user, uint blockNumber) external onlyController {
        transferBlockRelease[user] = blockNumber;
    }

    function setLockupTriggerAmount(uint256 amount) external onlyOwner {
        lockupTriggerAmt = amount;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
      ) internal override {
        require(block.number > transferBlockRelease[from], "transfer too soon after cross-chain mint");
        super._transfer(from, to, amount);
        ICore(core).checkHealth(from);
      }

    function mint(address to, uint amount) external onlyCoreAndLiquidation {
        if(amount > lockupTriggerAmt){
            transferBlockRelease[to] = block.number + transferBlockWait;
        }
        _mint(to, amount);
    }

    function burn(address from, uint amount) external onlyCoreAndLiquidation {
        require(block.number > transferBlockRelease[from], "burn too soon after cross-chain mint");
        _burn(from, amount);
    }
}
