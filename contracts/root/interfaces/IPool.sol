// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/// @title A LayerZero example sending a cross chain message from a source chain to a destination chain to increment a counter
interface IPool  {
    function deposit(bytes32 id, bytes32 chainId, address user, uint tokenAmount) external;
    function repay(bytes32 id, bytes32 chainId, address user, uint tokenAmount) external;
    function swap(bytes32 id, bytes32 srcChainId, bytes32 destChainId, uint tokenAmount) external;
    
}
