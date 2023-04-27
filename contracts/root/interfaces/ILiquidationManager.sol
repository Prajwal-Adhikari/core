// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "./IOracle.sol";

interface ILiquidationManager {
    /**
     * @notice Configures role manager address
     * This function can only be accessed by the owner.
     * @param roleManagerAddress - address of the roleManager contract.
     **/

    function setRoleManager(address roleManagerAddress) external;

    /**
     * @notice Configures core contract.
     * This function can only be accessed by the account with role SET_LIQUIDATION_METHOD
     * @param coreAddress - address of the core contract.
     **/
    function setCore(address coreAddress) external;

    /**
     * @notice Configures Oracle contract.
     * This function can only be accessed by the account with role SET_LIQUIDATION_METHOD
     * @param oracleAddress - address of the oracle contract.
     **/
    function setOracle(IOracle oracleAddress) external;

    /**
     * @notice Liquidates the position of address `user`.
     * @param user - the address whose position is to be liquidated
     * @param collateralId - the pool id of the collateral asset
     * @param debtId - the pool id of the debt asset
     * @param collateralAmount - the collateral user want to liquidate
     **/
    function liquidate(
        address user,
        bytes32 collateralId,
        bytes32 debtId,
        uint256 collateralAmount
    ) external;
}
