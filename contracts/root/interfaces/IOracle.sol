// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/// @title A LayerZero example sending a cross chain message from a source chain to a destination chain to increment a counter
interface IOracle {
    /**
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/

    function setRoleManager(address roleManagerAddress) external;

    /**
     * @notice Configures aggregator address for a asset `_id` managed by Chainlink
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _id - pool id of the asset
     * @param _aggregator - address of the aggregator
     **/
    function setAggregator(bytes32 _id, address _aggregator) external;

    /**
     * @notice Configures price feed contract
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _priceFeed - address of the price feed
     **/
    function setPriceFeed(address _priceFeed) external;

    /**
     * @notice Configures min max value to check against the oracle price
     * @param _id - pool id of the asset
     * @param _maxValue - accepted max value of asset
     * @param _minValue - accepted min value of asset
     **/
    function setMinMax(
        bytes32[] memory _id,
        uint256[] memory _maxValue,
        uint256[] memory _minValue
    ) external;

    /**
     * @notice Configures token address for asset with pool id `_id`
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _id - pool id of the asset
     * @param _assetAddress - address of the token
     **/
    function setAssetAddress(bytes32 _id, address _assetAddress) external;

    /**
     * @notice Configures stable coin id to be assosciated with asset with pool id `id`
     * which will be used as a pair for calculating price of that asset from the dex
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _id - pool id of the asset
     * @param _stable - pool id of the stable coin.
     **/
    function setStableCoinId(bytes32 _id, bytes32 _stable) external;

    /**
     * @notice Configures if the asset is a stable coin or not
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _id - pool id of the asset
     * @param _status - true if its a stable coin
     **/
    function setStableCoinStatus(bytes32 _id, bool _status) external;

    /**
     * @notice Configures router address of the dex
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _dexFactoryAddress - address of the dex factory contract.
     **/
    function setDexFactoryAddress(address _dexFactoryAddress) external;

    /**
     * @notice Sets fee and time interval.
     * @param _id - Pool id of the asset.
     * @param _fee - Fee.
     * @param _timeInterval - Time interval.
     **/
    function setFeeAndTimeInterval(
        bytes32 _id,
        uint24 _fee,
        uint32 _timeInterval
    ) external;

    /**
     * @notice Configures if the asset's price is to be fetched from dex or chainlink
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _id - pool id of the asset
     * @param _status - true if to be fetched from dex
     **/
    function setPriceSource(bytes32 _id, bool _status) external;

    /**
     * @notice Configures the accepted delay time for the chainlink data
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _maxDelayTime - max acceptable delayed time
     **/
    function setDelayTime(uint160 _maxDelayTime) external;

    /**
     * @notice Returns price of assets
     * @param _symbols - list of the asset's pool id
     **/
    function getPrices(
        bytes32[] memory _symbols
    ) external view returns (uint256[] memory);

    /**
     * @notice Returns price of an asset
     * @param _symbol - pool id of the asset
     **/
    function getSinglePrice(bytes32 _symbol) external view returns (uint256);

    /**
     * @notice Returns bool after checking the min max and zero condition
     * @param _symbol - pool id of the asset
     * @param _price - price return by the chainlink
     **/
    function priceCheck(
        bytes32 _symbol,
        uint256 _price
    ) external view returns (bool status);

    /**
     * @notice Returns price of the asset fetched from chainlink aggregator
     * @param _symbol - pool id of the asset
     **/
    function getPriceFromChainlink(
        bytes32 _symbol
    ) external view returns (uint256);

    /**
     * @notice Returns price of the asset fetched from dex
     * @param _symbol - pool id of the asset
     **/
    function getPriceFromDex(bytes32 _symbol) external view returns (uint256);
}
