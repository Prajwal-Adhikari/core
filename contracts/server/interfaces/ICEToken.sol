// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title A LayerZero example sending a cross chain message from a source chain to a destination chain to increment a counter
interface ICEToken {
    function mint(address to, uint amount) external;

    function burn(address from, uint amount) external;
}
