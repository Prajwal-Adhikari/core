// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface ILiquidationManager {
    function liquidate(address user, bytes32 collateralId, bytes32 debtId, uint debtAmount) external returns (uint, uint);
}