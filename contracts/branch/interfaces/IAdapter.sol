// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IAdapter {
    function get(bytes32 id, uint amount, address to) external;
    function send(bytes memory payload, address sender, uint gasValue, bytes32 route) external payable;

}