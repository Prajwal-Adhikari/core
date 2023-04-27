// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IRoleManager {
    /**
     * @notice Checks role for an account
     * Reverts if the account doesnt have permission of the role
     * @param role - role of contract.
     * @param account - address of user.
     **/
    function checkRole(bytes32 role, address account) external view;

    /**
     * @notice Returns bytes32 value of the public variable SET_BRANCH_METHOD
     **/
    function SET_BRANCH_METHOD() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable SET_ADAPTER_METHOD
     **/
    function SET_ADAPTER_METHOD() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable SET_ROUTE_METHOD
     **/
    function SET_ROUTE_METHOD() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable SET_POOL
     **/
    function SET_POOL() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable PROTOCOL_PAUSE
     **/
    function PROTOCOL_PAUSE() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable EMERGENCY_WITHDRAW
     **/
    function EMERGENCY_WITHDRAW() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable SWAP
     **/
    function SWAP() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable BRANCH
     **/
    function BRANCH() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable ADAPTER
     **/
    function ADAPTER() external view returns (bytes32);

    /**
     * @notice Returns bytes32 value of the public variable ROUTE
     **/
    function ROUTE() external view returns (bytes32);
}
