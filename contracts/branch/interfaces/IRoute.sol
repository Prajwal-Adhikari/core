// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IRoute {
    /**
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/

    /**
     * @notice Configures adapter contract.
     * This function can only be accessed by the account with role of SET_ROUTE_METHOD
     * @param adapterAddress - address of the adapter contract.
     **/
    function setAdapter(address adapterAddress) external;

    /**
     * @notice Configures gas value for LayerZero V1
     * This function can only be accessed by the account with role of SET_ROUTE_METHOD
     * @param _gasUsage - value of the gas
     **/
    function setGasUsage(uint256 _gasUsage) external;

    /**
     * @notice Configures gas value for LayerZero V2
     * This function can only be accessed by the contract owner.
     * @param _gas value of the gas
     * @param _value value of the gas
     **/
    function setExecutorValues(
        uint128 _gas,
        uint128 _value
    ) external;

    /**
     * @notice Sends payload from route to destination chain.
     * This function can only be accessed by the account with role of ADAPTER
     * @param payload - information to be passed
     * @param sender - address of the user
     * @param airdropAmount - amount to be sent to destination chain
     **/
    function send(
        bytes memory payload,
        address sender,
        uint256 airdropAmount
    ) external payable;

    /*
     * @notice Encodes the message type and returns the cross chain messaging fee for LayerZero V1
     * @param funtionType - message type, either deposit,repay or swap information
     * @param airdropAmount - amount to be airdropped to destination chain
     **/
    function estimateFees(
        uint8 functionType,
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
