// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


interface IFeeProvider {
    function getFeeAmount(uint16 _chainId, bytes32 _poolId) external view returns (uint);
}