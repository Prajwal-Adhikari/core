// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ICEToken.sol";

contract Controller is Ownable {
    address[] public ceTokens;
    mapping(address => bool) public ceTokenExist;

    event CagedUser(address indexed user);
    event ReleaseCage(address indexed user);

    function addCEToken(address[] memory _ceTokens) external onlyOwner {
        for (uint i = 0; i < _ceTokens.length; i++) {
            if (!ceTokenExist[_ceTokens[i]]) {
                ceTokens.push(_ceTokens[i]);
                ceTokenExist[_ceTokens[i]] = true;
            }
        }
    }

    function removeCEToken(address _ceToken) external onlyOwner {
        address lastElement = ceTokens[ceTokens.length - 1];
        for (uint i = 0; i < ceTokens.length; i++) {
            if (ceTokens[i] == _ceToken) {
                ceTokens[i] = lastElement;
                ceTokenExist[_ceToken] = false;
                ceTokens.pop();
                return;
            }
        }
    }

    function cageUser(address user) external onlyOwner {
        for (uint i = 0; i < ceTokens.length; i++) {
            ICEToken(ceTokens[i]).setTransferBlockRelease(user, 2 ** 256 - 1);
        }
        emit CagedUser(user);
    }

    function releaseCage(address user) external onlyOwner {
        for (uint i = 0; i < ceTokens.length; i++) {
            ICEToken(ceTokens[i]).setTransferBlockRelease(user, block.number);
        }
        emit ReleaseCage(user);
    }
}
