// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DebtToken is ERC20, Ownable {
    address public core;
    address public liquidationManager;
    uint public balanceScale = 1e18;
    uint constant public MAG = 1e18;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
    }

    modifier onlyCoreAndLiquidation() {
        require(msg.sender == core || msg.sender == liquidationManager, "Permission denied");
        _;
    }

    function initialize(address _core, address _liquidationManager) external onlyOwner {
        core = _core;
        liquidationManager = _liquidationManager;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal pure override {
        (from, to, amount);
        require(false, "Cannot transfer debt token");
    }

    function mint(address to, uint amount) external onlyCoreAndLiquidation {
        _mint(to, amount);
    }

    function burn(address from, uint amount) external onlyCoreAndLiquidation {
        _burn(from, amount);
    }
}