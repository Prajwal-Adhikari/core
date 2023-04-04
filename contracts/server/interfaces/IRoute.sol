// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IRoute {
    function sendToken(bytes32 id, bytes32 chainId, bytes32 user, address sender, uint amount) external payable;

    
}