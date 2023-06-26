// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// this is a MOCK
contract ERC20Meme is ERC20 {
    uint8 public customDecimals = 18;
    address public admin;
    uint256 fraction = 10;

    constructor(string memory name_, string memory symbol_, uint8 _decimals) ERC20(name_, symbol_) {
        customDecimals = _decimals;
        admin = msg.sender;
    }

    function mint(address _to, uint _amount) public {
        _mint(_to, _amount);
    }

    function decimals() public view override returns (uint8) {
        return customDecimals;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        (uint256 amountTo, uint256 amountAdmin) = splitAmount(amount);
        _transfer(owner, to, amountTo);
        _transfer(owner, admin, amountAdmin);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
         (uint256 amountTo, uint256 amountAdmin) = splitAmount(amount);
        _transfer(from, to, amountTo);
        _transfer(from, admin, amountAdmin);
        return true;
    }

    function splitAmount(uint256 amount) public view returns(uint256 amountTo, uint256 amountAdmin){
        amountAdmin = (amount*fraction)/(100);
        amountTo = amount-amountAdmin;
    }
}
