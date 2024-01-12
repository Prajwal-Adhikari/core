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
     * @notice Configures gas value for LayerZero V1
     * This function can only be accessed by the account with role SET_ROUTE_METHOD.
     * @param gasUsage - value of the gas
     **/
    function setGasUsage(uint256 gasUsage) external;

    /**
     * @notice Configures gas value for LayerZero V2
     * This function can only be accessed by the contract owner.
     * @param _gas value of the gas
     * @param _value value of the gas
     **/
    function setExecutorValues(uint128 _gas, uint128 _value) external;

    /**
     * @notice Links chainId with chain name.
     * This function can only be accessed by the account with role SET_ROUTE_METHOD.
     * @param chain - name of the chain.
     * @param id - chain id of the chain.
     **/
    function setChainKeyID(bytes32 chain, uint16 id) external;

    /**
     * @notice Sends payload to destination chain
     * This function can only be accessed by the account with role ADAPTER.
     * @param payload - information to be sent to destination
     * @param chainId - id of the destination chain.
     * @param sender - address of tx sender
     * @param airdropAmount - amount to be airdropped to destination chain
     * @param airdropReceiver - receiver of the airdrop
     **/
    function send(
        bytes memory payload,
        bytes32 chainId,
        address sender,
        uint256 airdropAmount,
        address airdropReceiver
    ) external payable;

    /**
     * @notice Returns the estimated transaction fees to send a cross chain message to
     * the destination chain with chain id `chainId` for LayerZero V1
     * @param chainId - chain id of the destionation chain.
     * @param airdropAmount - amount to be airdropped to destination chain
     **/
    function estimateFees(
        bytes32 chainId,
        uint256 airdropAmount
    ) external view returns (uint256);

    /* @notice Quotes the gas needed to pay for the full omnichain transaction for LayerZero V2
     * @return nativeFee Estimated gas fee in native gas.
     * @return lzTokenFee Estimated gas fee in ZRO token.
     */
    function quote(
        uint32 _dstEid, // Destination chain's endpoint ID.
        bytes calldata _payload, // The message to send.
        uint128 airdropAmount,
        address airdropReceiver,
        bool _payInLzToken // boolean for which token to return fee in
    ) external view returns (uint256 , uint256);
}
