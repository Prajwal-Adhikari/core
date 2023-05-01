// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "./IOracle.sol";

interface ILiquidationManager {
    /**
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
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
     * @param user - borrower address whose position is to be liquidated
     * @param collateralId - the pool id of the collateral asset of borrower
     * @param debtId - the pool id of the borrowed asset of borrower
     * @param borrowerCollateral - amount of collateral of collateralId, the liquidator wants to liquidate
     **/
    function liquidate(
        address user,
        bytes32 collateralId,
        bytes32 debtId,
        uint256 borrowerCollateral
    ) external;
}
