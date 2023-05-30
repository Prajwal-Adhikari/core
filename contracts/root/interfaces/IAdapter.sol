// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IAdapter {
    /**
     * @notice Configures role manager.
     * This function can only be accessed by account with role DEFAULT_ADMIN_ROLE
     * @param roleManagerAddress - address of the role manager contract
     **/

    function setRoleManager(address roleManagerAddress) external;

    /**
     * @notice Configures pool contract.
     * This function can only be accessed by account with role SET_ADAPTER_METHOD.
     * @param _poolAddress - address of the pool contract.
     **/
    function setPool(address _poolAddress) external;

    /**
     * @notice Configures route.
     * This function can only be accessed by account with role SET_ADAPTER_METHOD.
     * @param route - name of the route
     * @param routeAddress - address of the route contract.
     **/
    function setRoute(bytes32 route, address routeAddress) external;

    /**
     * @notice Sends payload to the pool contract.
     * This function can only be accessed by account with role ROUTE.
     * @param payload - information containing data , pool id and token amount
     * @param chainId - chain id of the source chain
     * @param route - communication protocol through which payload is received
     **/
    function execute(bytes memory payload, bytes32 chainId, bytes32 route) external;

    /**
     * @notice Sends swap information from adapter to route
     * This function can only be accessed by account with role POOL.
     * @param payload - information containing receipient address, pool id and token amount
     * @param chainId - chain id of the destination chain
     * @param sender - user address
     * @param airdropAmount - amount to be airdropped to destination chain
     * @param airdropReceiver - receiver of the airdrop
     * @param route - communication protocol
     **/
    function send(
        bytes memory payload,
        bytes32 chainId,
        address sender,
        uint256 airdropAmount,
        address airdropReceiver,
        bytes32 route
    ) external payable;
}
