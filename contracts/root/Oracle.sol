// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "./interfaces/IUniswapV3Factory.sol";
import "./libraries/OracleLibrary.sol";
import "./interfaces/IRoleManager.sol";

interface IERC20 {
    function decimals() external view returns (uint8);
}

string constant TAG = "Oracle";

interface DexRouter {
    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

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

    error PriceNotSet(bytes32 symbol);
    error ChainlinkMalfunction(bytes32 symbol);
    error RoundNotComplete(bytes32 symbol);
    error StaleData(bytes32 symbol);
    error PoolNotExist(bytes32 symbol);
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

    function initialize(address roleManagerAddress) public initializer {
        roleManager = roleManagerAddress;
    }

    function setRoleManager(
        address roleManagerAddress
    ) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    function setAggregator(
        bytes32 _id,
        address _aggregator
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        aggregator[_id] = _aggregator;
    }

    function setAssetAddress(
        bytes32 _id,
        address _assetAddress
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        assetAddress[_id] = _assetAddress;
    }

    function setStableCoinId(
        bytes32 _id,
        bytes32 _stable
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        stableCoinId[_id] = _stable;
    }

    function setStableCoinStatus(
        bytes32 _id,
        bool _status
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        isStableCoin[_id] = _status;
    }

    function setDexFactoryAddress(
        address _dexFactoryAddress
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        dexFactoryAddress = _dexFactoryAddress;
    }

    function setFeeAndTimeInterval(
        bytes32 _id,
        uint24 _fee,
        uint32 _timeInterval

    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        fee[_id] = _fee;
        timeInterval[_id] = _timeInterval;
    }

    function setPriceSource(
        bytes32 _id,
        bool _status
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        fetchFromDex[_id] = _status;
    }

    function getPrices(
        bytes32[] memory _symbols
    ) external view returns (uint256[] memory results) {
        results = new uint256[](_symbols.length);
        uint256 price;
        for (uint256 i; i < _symbols.length; i++) {
            if (fetchFromDex[_symbols[i]]) {
                if (isStableCoin[_symbols[i]]) {
                    price = 1e18;
                } else {
                    price = getPriceFromDex(_symbols[i]);
                }
            } else {
                price = getPriceFromChainlink(_symbols[i]);
            }
            // require(price > 0, string.concat(TAG, ": Price not set up"));
            if(price == 0)
                revert PriceNotSet(_symbols[i]);
            results[i] = price;
        }
    }

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
            // require(result > 0, string.concat(TAG, ": Price not set up"));
            if(result == 0)
                revert PriceNotSet(_symbol);
            
        }
    

    function getPriceFromChainlink(
        bytes32 _symbol
    ) public view returns (uint256) {
        // prettier-ignore
        (
            uint80 roundID,
            int256 basePrice,
            /*uint startedAt*/,
            uint timeStamp,
            uint80 answeredInRound
        ) =
         AggregatorV3Interface(
            aggregator[_symbol]
        ).latestRoundData();

        // require(basePrice != 0, string.concat(TAG, ": Chainlink Malfunction"));
        // require(timeStamp != 0, string.concat(TAG, ": Round is not complete"));
        // require(answeredInRound >= roundID, string.concat(TAG, ": Stale data"));

        if(basePrice == 0)
            revert ChainlinkMalfunction(_symbol);

        if(timeStamp == 0)
            revert RoundNotComplete(_symbol);

        if(answeredInRound < roundID)
            revert StaleData(_symbol);

        uint8 quoteDecimals = AggregatorV3Interface(aggregator[_symbol])
            .decimals();
        uint256 quotePrice = _scalePrice(
            uint256(basePrice),
            quoteDecimals,
            ROOT_DECIMALS
        );

        return quotePrice;
    }

    function getPriceFromDex(
        bytes32 _symbol
    ) public view returns (uint256) {

        address pool = IUniswapV3Factory(dexFactoryAddress).getPool(
            assetAddress[_symbol],
            assetAddress[stableCoinId[_symbol]],
            fee[_symbol]
        );
        // require(pool != address(0), string.concat(TAG, ": Pool doesn't exist"));
        if(pool == address(0))
            revert PoolNotExist(_symbol);

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
