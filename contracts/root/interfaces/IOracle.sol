// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/// @title A LayerZero example sending a cross chain message from a source chain to a destination chain to increment a counter
interface IOracle  {
    /**
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/

    function setRoleManager(address roleManagerAddress) external;

    /**
     * @notice Configures router address of the dex
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _dexFactoryAddress - address of the dex factory contract.
     **/
    function setDexFactoryAddress(
        address _dexFactoryAddress
    ) external;

    /**
     * @notice Configures aggregator address for a asset `_id` managed by Chainlink
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _id - pool id of the asset
     * @param _aggregator - address of the aggregator
     **/
    function setAggregator(
        bytes32 _id,
        address _aggregator
    ) external;

    /**
    * @notice Configures token address for asset with pool id `_id` 
    * This function can only be accessed by the account with role SET_ORACLE_METHOD.
    * @param _id - pool id of the asset
    * @param _assetAddress - address of the token
    **/
    function setAssetAddress(
        bytes32 _id,
        address _assetAddress
    ) external;

    /**
    * @notice Configures stable coin id to be assosciated with asset with pool id `id` 
    * which will be used as a pair for calculating price of that asset from the dex
    * This function can only be accessed by the account with role SET_ORACLE_METHOD.
    * @param _id - pool id of the asset
    * @param _stable - pool id of the stable coin.
    **/
    function setStableCoinId(
        bytes32 _id,
        bytes32 _stable
    ) external;

    /**
    * @notice Configures if the asset is a stable coin or not
    * This function can only be accessed by the account with role SET_ORACLE_METHOD.
    * @param _id - pool id of the asset
    * @param _status - true if its a stable coin
    **/
    function setStableCoinStatus(
        bytes32 _id,
        bool _status
    ) external;

    /**
    * @notice Configures if the asset's price is to be fetched from dex or chainlink
    * This function can only be accessed by the account with role SET_ORACLE_METHOD.
    * @param _id - pool id of the asset
    * @param _status - true if to be fetched from dex
    **/
    function setPriceSource(
        bytes32 _id,
        bool _status
    ) external;


    /**
    * @notice Returns price of assets
    * @param _symbols - list of the asset's pool id
    **/
    function getPrices(bytes32[] memory _symbols) external view returns(uint256[] memory);

    /**
    * @notice Returns price of an asset
    * @param _symbol - pool id of the asset
    **/
    function getSinglePrice(
        bytes32 _symbol
    ) external view returns (uint256);

    /**
    * @notice Returns price of the asset fetched from chainlink aggregator
    * @param _symbol - pool id of the asset
    **/
    function getPriceFromChainlink(bytes32 _symbol) external view returns(uint256);

    /**
    * @notice Returns price of the asset fetched from dex
    * @param _symbol - pool id of the asset
    **/
    function getPriceFromDex(bytes32 _symbol) external view returns(uint256);
}
