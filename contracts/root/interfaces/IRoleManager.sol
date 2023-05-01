// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IRoleManager {
    /**
     * @notice Sets new adminRole for a role
     * This function can be called by the account having adminRole for the `role`
     * @param role - particular role 
     * @param adminRole - new role to be assigned as admin
     **/
    function setRoleAdmin(
        bytes32 role,
        bytes32 adminRole
    ) external;

    /**
     * @notice Checks role for an account
     * Reverts if the account doesnt have permission of the role
     * @param role - role of contract.
     * @param account - address of user.
     **/
    function checkRole(bytes32 role, address account) external view ;

     /**
     * @notice Returns bytes32 value of the public variable DEFAULT_ADMIN_ROLE
     **/
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable SET_POOL_METHOD
     **/
    function SET_POOL_METHOD() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable SET_CORE_METHOD
     **/
    function SET_CORE_METHOD() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable SET_ADAPTER_METHOD
     **/
    function SET_ADAPTER_METHOD() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable SET_ROUTE_METHOD
     **/
    function SET_ROUTE_METHOD() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable SET_LIQUIDATION_METHOD
     **/
    function SET_LIQUIDATION_METHOD() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable SET_FEEPROVIDER_METHOD
     **/
    function SET_FEEPROVIDER_METHOD() external view returns (bytes32);

     /**
     * @notice Returns bytes32 value of the public variable SET_ORACLE_METHOD
     **/
    function SET_ORACLE_METHOD() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable SET_CE_TOKEN_METHOD
     **/
    function SET_CE_TOKEN_METHOD() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable SET_CONTROLLER_METHOD
     **/
    function SET_CONTROLLER_METHOD() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable INIT_POOL
     **/
    function INIT_POOL() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable POOL_STATUS
     **/
    function POOL_STATUS() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable PROTOCOL_PAUSE
     **/
    function PROTOCOL_PAUSE() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable MINT_BURN_CE_DEBT_TOKEN
     **/
    function MINT_BURN_CE_DEBT_TOKEN() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable POOL
     **/
    function POOL() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable CORE
     **/
    function CORE() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable LIQUIDATION_MANAGER
     **/
    function LIQUIDATION_MANAGER() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable FEE_PROVIDER
     **/
    function FEE_PROVIDER() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable ADAPTER
     **/
    function ADAPTER() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable ROUTE
     **/
    function ROUTE() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable CONTROLLER
     **/
    function CONTROLLER() external view returns (bytes32);




}
