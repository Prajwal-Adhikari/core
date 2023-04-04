// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


interface IFeeProvider {
    function getFeeAmount(bytes32  _chainId, bytes32 _poolId) external view returns (uint);
}