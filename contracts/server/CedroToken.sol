// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CedroToken is ERC20{
    constructor(uint256 _totalSupply) ERC20("CedroToken", "CDT"){
        _mint(msg.sender,_totalSupply);
    }
}
