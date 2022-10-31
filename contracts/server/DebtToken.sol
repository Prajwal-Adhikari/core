// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPool.sol";

contract DebtToken is ERC20, Ownable {
    address public pool;
    address public treasury;
    uint public balanceScale = 1e18;
    uint constant public MAG = 1e18;

    mapping(address => uint) balanceDebt;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
    }

    modifier onlyPool() {
        require(msg.sender == pool, "Permission denied");
        _;
    }

    function initialize(address _pool, address _treasury) external onlyOwner {
        pool = _pool;
        treasury = _treasury;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(false, "Cannot transfer debt token");
    }

    function mint(address to, uint amount) external onlyPool {
        _mint(to, amount);
    }

    function burn(address from, uint amount) external onlyPool {
        _burn(from, amount);
    }
}
