// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ICEToken.sol";

contract Controller is Ownable{

    address public immutable ceToken;

    event CagedUser(address indexed user);
    event ReleaseCage(address indexed user);

    constructor(address _ceToken) {
        require(_ceToken != address(0), "Controller: invalid address");
        ceToken = _ceToken;
    }

    function cageUser(address user) external onlyOwner {
        ICEToken(ceToken).setTransferBlockRelease(user, 2**256 - 1);
        emit CagedUser(user);
    }
    function releaseCage(address user) external onlyOwner {
        ICEToken(ceToken).setTransferBlockRelease(user, block.number);
        emit ReleaseCage(user);
    }
}