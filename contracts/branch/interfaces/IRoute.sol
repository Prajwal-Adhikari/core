// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IRoute {
    /**
     * @notice Configures role manager address
     * This function can only be accessed by the owner.
     * @param roleManagerAddress - address of the roleManager contract.
     **/

    /**
     * @notice Configures adapter contract.
     * This function can only be accessed by the account with role of SET_ROUTE_METHOD
     * @param adapterAddress - address of the adapter contract.
     **/
    function setAdapter(address adapterAddress) external;

    /**
     * @notice Configures gas value.
     * This function can only be accessed by the account with role of SET_ROUTE_METHOD
     * @param _gasUsage - value of the gas
     **/
    function setGasUsage(uint256 _gasUsage) external;

    /**
     * @notice Configures name of the root chain and destination contract address
     * This function can only be accessed by the account with role of SET_ROUTE_METHOD
     * @param name - name of the root chain.
     * @param addr - route address in the root chain
     **/
    function setRootChainNameAddress(
        string calldata name,
        string calldata addr
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
     * @notice Encodes the message type and returns the cross chain messaging fee for LayerZero.
     * @param funtionType - message type, either deposit,repay or swap information
     * @param airdropAmount - amount to be airdropped to destination chain
     **/
    function estimateFees(
        uint8 functionType,
        uint256 airdropAmount
    ) external view returns (uint256);
}
