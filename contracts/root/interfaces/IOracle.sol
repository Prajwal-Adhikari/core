// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/// @title A LayerZero example sending a cross chain message from a source chain to a destination chain to increment a counter
interface IOracle  {
    function getPrices(bytes32[] memory _symbols) external view returns(uint256[] memory);
    function getSinglePrice(bytes32 _symbol) external view returns(uint256 result);
}
