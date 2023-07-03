// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IAdapter {

    /**
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/

    function setRoleManager(address roleManagerAddress) external;
    /**
     * @notice Configures route address for corresponding route.
     * This function can only be accessed by account with role SET_ADAPTER_METHOD.
     * @param route - name of the route
     * @param routeAddress - address of the route contract.
     **/
    function setRoute(bytes32 route, address routeAddress) external;

    /**
     * @notice Configures branch contract.
     * This function can only be accessed by account with role SET_ADAPTER_METHOD.
     * @param branchAddress - address of the branch contract.
     **/
    function setBranch(address branchAddress) external;

    /**
     * @notice Sends payload from branch to selected route.
     * This function can only be accessed by account with role BRANCH.
     * @param payload - information to be passed
     * @param sender - address of the user
     * @param airdropAmount - amount to be sent to the destination chain
     * @param route - communication protocol
     **/
    function send(
        bytes memory payload,
        address sender,
        uint256 airdropAmount,
        bytes32 route
    ) external payable;

    /**
     * @notice Sends payload from route to branch.
     * This function can only be accessed by account with role ROUTE.
     * @param payload - information of token amount and receipient.
     **/
    function execute(bytes memory payload) external;
}
