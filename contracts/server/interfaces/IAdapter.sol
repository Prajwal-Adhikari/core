// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IAdapter {
    function deposit(bytes32 id, bytes32 chainId, address user, uint tokenAmount) external;
    function repay(bytes32 id, bytes32 chainId, address user, uint tokenAmount) external;
    function sendToken(bytes32 id,bytes32 chainId, bytes32 user, address sender, uint amount, bytes32 route) external payable;

}