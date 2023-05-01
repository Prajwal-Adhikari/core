// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IRoute {
    /**
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/

    function setRoleManager(address roleManagerAddress) external;

    /**
     * @notice Configures adapter contract.
     * This function can only be accessed by the account with role SET_ROUTE_METHOD.
     * @param adapterAddress - address of the adapter contract.
     **/
    function setAdapter(address adapterAddress) external;

    /**
     * @notice Configures gas value.
     * This function can only be accessed by the account with role SET_ROUTE_METHOD.
     * @param gasUsage - value of the gas
     **/
    function setGasUsage(uint256 gasUsage) external;

    /**
     * @notice Links chainId with chain name.
     * This function can only be accessed by the account with role SET_ROUTE_METHOD.
     * @param chain - name of the chain.
     * @param id - chain id of the chain.
     **/
    function setChainNameID(bytes32 chain, uint16 id) external;

    /**
     * @notice Links chain key with chain name and destination contract
     * This function can only be accessed by the account with role SET_ROUTE_METHOD.
     * @param chainId id of the chain.
     * @param name name of the chain.
     * @param addr address of the destination contract
     **/
    function setDestChainIdNameAddress(
        bytes32 chainId,
        string calldata name,
        string calldata addr
    ) external;

    /**
     * @notice Sends payload to destination chain
     * This function can only be accessed by the account with role ADAPTER.
     * @param payload - information to be sent to destination
     * @param chainId - id of the destination chain.
     * @param sender - address of tx sender
     * @param airdropAmount - amount to be airdropped to destination chain
     **/

    function send(
        bytes memory payload,
        bytes32 chainId,
        address sender,
        uint256 airdropAmount
    ) external payable;

    /**
     * @notice Returns the estimated transaction fees to send a cross chain message to
     * the destination chain with chain id `chainId`.
     * @param chainId - chain id of the destionation chain.
     * @param airdropAmount - amount to be airdropped to destination chain
     **/
    function estimateFees(
        bytes32 chainId,
        uint256 airdropAmount
    ) external view returns (uint256);
}
