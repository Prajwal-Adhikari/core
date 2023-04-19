// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IRoute {
    function send(bytes memory payload, address sender, uint airdropAmount) external payable;

    
}