// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "./interfaces/IUniswapV3Factory.sol";
import "./libraries/OracleLibrary.sol";
import "./interfaces/IRoleManager.sol";

string constant TAG = "Oracle";

interface IERC20 {
    function decimals() external view returns (uint8);
}

interface DexRouter {
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
}

/**
* @title Oracle contract
* @notice Used to get real time price of an asset
**/
contract Oracle is Initializable, ContextUpgradeable {
    uint8 public constant ROOT_DECIMALS = 18;

    mapping(bytes32 => address) public aggregator;
    mapping(bytes32 => address) public assetAddress;
    mapping(bytes32 => bytes32) public stableCoinId;
    mapping(bytes32 => bool) public isStableCoin;
    mapping(bytes32 => bool) public fetchFromDex;
    mapping(bytes32 => uint256) public prices;
    mapping(bytes32 => uint24) public fee;
    mapping(bytes32 => uint32) public timeInterval;

    address public dexFactoryAddress;
    address public roleManager;

    event SetPrice(bytes32 symbol, uint256 price);

    error PriceNotSet(string contractTAG, bytes32 symbol);
    error ChainlinkMalfunction(string contractTAG, bytes32 symbol);
    error RoundNotComplete(string contractTAG, bytes32 symbol);
    error StaleData(string contractTAG, bytes32 symbol);
    error PoolNotExist(string contractTAG, bytes32 symbol);
    /**
     * @dev Modifier that checks if caller has a specific role.
     **/
    modifier onlyRole(bytes32 role) {
        IRoleManager(roleManager).checkRole(role, _msgSender());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initilize the contract.
     * @param roleManagerAddress - The EOA of role manager.
     **/
    function initialize(address roleManagerAddress) public initializer {
        roleManager = roleManagerAddress;
    }

    /**
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/
    function setRoleManager(
        address roleManagerAddress
    ) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    /**
     * @notice Configures aggregator address for a asset `_id` managed by Chainlink
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _id - pool id of the asset
     * @param _aggregator - address of the aggregator
     **/
    function setAggregator(
        bytes32 _id,
        address _aggregator
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        aggregator[_id] = _aggregator;
    }

    /**
    * @notice Configures token address for asset with pool id `_id` 
    * This function can only be accessed by the account with role SET_ORACLE_METHOD.
    * @param _id - pool id of the asset
    * @param _assetAddress - address of the token
    **/
    function setAssetAddress(
        bytes32 _id,
        address _assetAddress
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        assetAddress[_id] = _assetAddress;
    }

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
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        stableCoinId[_id] = _stable;
    }

    /**
    * @notice Configures if the asset is a stable coin or not
    * This function can only be accessed by the account with role SET_ORACLE_METHOD.
    * @param _id - pool id of the asset
    * @param _status - true if its a stable coin
    **/
    function setStableCoinStatus(
        bytes32 _id,
        bool _status
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        isStableCoin[_id] = _status;
    }

    /**
     * @notice Configures router address of the dex
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _dexFactoryAddress - address of the dex factory contract.
     **/
    function setDexFactoryAddress(
        address _dexFactoryAddress
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        dexFactoryAddress = _dexFactoryAddress;
    }

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

    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        fee[_id] = _fee;
        timeInterval[_id] = _timeInterval;
    }

    /**
    * @notice Configures if the asset's price is to be fetched from dex or chainlink
    * This function can only be accessed by the account with role SET_ORACLE_METHOD.
    * @param _id - pool id of the asset
    * @param _status - true if to be fetched from dex
    **/
    function setPriceSource(
        bytes32 _id,
        bool _status
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        fetchFromDex[_id] = _status;
    }

    /**
    * @notice Returns price of assets
    * @param _symbols - list of the asset's pool id
    **/
    function getPrices(
        bytes32[] memory _symbols
    ) external view returns (uint256[] memory results) {
        results = new uint256[](_symbols.length);
        uint256 price;
        for (uint256 i; i < _symbols.length; i++) {
            if (fetchFromDex[_symbols[i]]) {
                if (isStableCoin[_symbols[i]]) {
                    price = getPriceFromChainlink(_symbols[i]);
                } else {
                    price = getPriceFromDex(_symbols[i]);
                }
            } else {
                price = getPriceFromChainlink(_symbols[i]);
            }
            if(price == 0)
                revert PriceNotSet(TAG, _symbols[i]);
            results[i] = price;
        }
    }

    /**
    * @notice Returns price of an asset
    * @param _symbol - pool id of the asset
    **/
    function getSinglePrice(
        bytes32 _symbol
    ) external view returns (uint256 result) {
            if (fetchFromDex[_symbol]) {
                if (isStableCoin[_symbol]) {
                    result = getPriceFromChainlink(_symbol);
                } else {
                    result = getPriceFromDex(_symbol);
                }
            } else {
                result = getPriceFromChainlink(_symbol);
            }
            if(result == 0)
                revert PriceNotSet(TAG, _symbol);
            
        }
    
    /**
    * @notice Returns price of the asset fetched from chainlink aggregator
    * @param _symbol - pool id of the asset
    **/
    function getPriceFromChainlink(
        bytes32 _symbol
    ) public view returns (uint256) {
        // prettier-ignore
        (
            uint80 roundID,
            int256 basePrice,
            /*uint256 startedAt*/,
            uint256 timeStamp,
            uint80 answeredInRound
        ) =
         AggregatorV3Interface(
            aggregator[_symbol]
        ).latestRoundData();

        if(basePrice == 0)
            revert ChainlinkMalfunction(TAG, _symbol);

        if(timeStamp == 0)
            revert RoundNotComplete(TAG, _symbol);

        if(answeredInRound < roundID)
            revert StaleData(TAG, _symbol);

        uint8 quoteDecimals = AggregatorV3Interface(aggregator[_symbol])
            .decimals();
        uint256 quotePrice = _scalePrice(
            uint256(basePrice),
            quoteDecimals,
            ROOT_DECIMALS
        );

        return quotePrice;
    }

    /**
    * @notice Returns price of the asset fetched from dex
    * @param _symbol - pool id of the asset
    **/
    function getPriceFromDex(
        bytes32 _symbol
    ) public view returns (uint256) {

        address pool = IUniswapV3Factory(dexFactoryAddress).getPool(
            assetAddress[_symbol],
            assetAddress[stableCoinId[_symbol]],
            fee[_symbol]
        );
        if(pool == address(0))
            revert PoolNotExist(TAG, _symbol);

        int24 tick = OracleLibrary.consult(pool, timeInterval[_symbol]);

        uint8 baseDecimals = IERC20(assetAddress[_symbol]).decimals();
        uint256 amountOut = OracleLibrary.getQuoteAtTick(
            tick,
            uint128(10 ** baseDecimals),
            assetAddress[_symbol],
            assetAddress[stableCoinId[_symbol]]
        );

        uint8 quoteDecimals = IERC20( assetAddress[stableCoinId[_symbol]]).decimals();
        uint256 quotePrice = _scalePrice(
            amountOut,
            quoteDecimals,
            ROOT_DECIMALS
        );

        uint256 stableCoinPrice = getPriceFromChainlink(stableCoinId[_symbol]);

        quotePrice = (quotePrice * stableCoinPrice)/ (10 ** ROOT_DECIMALS );

        return quotePrice;

    }

    function _scalePrice(
        uint256 _price,
        uint8 _priceDecimals,
        uint8 _decimals
    ) internal pure returns (uint256) {
        if (_priceDecimals < _decimals) {
            return _price * uint256(10 ** (_decimals - _priceDecimals));
        } else if (_priceDecimals > _decimals) {
            return _price / uint256(10 ** (_priceDecimals - _decimals));
        }
        return _price;
    }
}
