// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/// @title A LayerZero example sending a cross chain message from a source chain to a destination chain to increment a counter
interface IPriceFeed {
    /**
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/
    function setRoleManager(address roleManagerAddress) external;

    /**
     * @notice Configures the prices of assets
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _symbols - list of pool ids of the assets
     * @param _prices - prices of the asset
     **/
    function setPrices(
        bytes32[] memory _symbols,
        uint256[] memory _prices
    ) external;

    /**
     * @notice Configures the prices of assets
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _symbol - pool id of the asset
     * @param _price - price of the asset
     **/
    function setPrice(bytes32 _symbol, uint256 _price) external;

    /**
     * @notice Returns price of assets
     * @param _symbols - list of the asset's pool id
     **/
    function getPrices(
        bytes32[] memory _symbols
    ) external view returns (uint256[] memory results);

    /**
     * @notice Returns price of an asset
     * @param _symbol - pool id of the asset
     **/
    function getPrice(bytes32 _symbol) external view returns (uint256 result);
}
