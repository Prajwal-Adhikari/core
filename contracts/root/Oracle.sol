// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "./interfaces/IRoleManager.sol";
import "./interfaces/IPriceFeed.sol";

string constant TAG = "Oracle";

interface IERC20 {
    function decimals() external view returns (uint8);
}

/**
* @title Oracle contract
* @notice Used to get real time price of an asset
**/
contract Oracle is Initializable, ContextUpgradeable {
    uint8 public constant ROOT_DECIMALS = 18;
    uint256 public GRACE_PERIOD_TIME;
    address public roleManager;
    address public priceFeed;
    address public sequencerUptimeFeed;

    mapping(bytes32 => address) public aggregator;
    mapping(bytes32 => bool) public fetchFromPriceFeed;
    mapping(bytes32 => uint256) public maxValue;
    mapping(bytes32 => uint256) public minValue;
    mapping(bytes32 => uint256) public heartBeatValue;

    error ChainlinkMalfunction(string contractTAG, bytes32 symbol);
    error RoundNotComplete(string contractTAG, bytes32 symbol);
    error StaleData(string contractTAG, bytes32 symbol);
    error PriceOutDated(string contractTAG, bytes32 symbol);
    error PoolNotExist(string contractTAG, bytes32 symbol);
    error PriceNotValid(string contractTAG, bytes32 symbol);
    error ArrayLengthMismatched(string contractTAG);
    error SequencerDown(string contractTAG);
    error GracePeriodNotOver(string contractTAG);
    
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
     * @param roleManagerAddress - Address of the roleManager contract.
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
     * @notice Configures price feed contract
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _priceFeed - address of the price feed
     **/
    function setPriceFeed(
        address _priceFeed
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        priceFeed = _priceFeed;
    }

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
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        if(_id.length != _maxValue.length || _id.length != _minValue.length )
            revert ArrayLengthMismatched(TAG);
        for (uint256 i; i < _id.length; i++) {
            maxValue[_id[i]] = _maxValue[i];
            minValue[_id[i]] = _minValue[i];
        }
    }

    /**
     * @notice Configures heart beat value to check against the oracle price
     * @param _id - pool id of the asset
     * @param _heartBeatValue - accepted max delay time of asset
     **/
    function setHeartBeat(
        bytes32[] memory _id,
        uint256[] memory _heartBeatValue
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        if(_id.length != _heartBeatValue.length)
            revert ArrayLengthMismatched(TAG);
        for (uint256 i; i < _id.length; i++) {
            heartBeatValue[_id[i]] = _heartBeatValue[i];
        }
    }

    /**
    * @notice Configures the grace period
    * This function can only be accessed by the account with role SET_ORACLE_METHOD.
    * @param  _gracePeriodTime - grace period
    **/
    function setGracePeriodTime(
        uint256 _gracePeriodTime
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        GRACE_PERIOD_TIME =  _gracePeriodTime;
    }

    /**
    * @notice Configures the sequencer uptime feed proxy address of L2 network
    * This function can only be accessed by the account with role SET_ORACLE_METHOD.
    * @param _upTimeFeed - address of the uptimeFeed
    **/
    function setSequencerUptimeFeed(
        address _upTimeFeed
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        sequencerUptimeFeed = _upTimeFeed;
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
            if (fetchFromPriceFeed[_symbols[i]]) {
                price = getPriceFromPriceFeed(_symbols[i]);
            } else {
                price = getPriceFromChainlink(_symbols[i]);
            }
           
           if(priceCheck(_symbols[i],price))
                revert PriceNotValid(TAG, _symbols[i]); 
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
        if (fetchFromPriceFeed[_symbol]) {
                result = getPriceFromPriceFeed(_symbol);
            } else {
                result = getPriceFromChainlink(_symbol);
            }
        if(priceCheck(_symbol,result))
            revert PriceNotValid(TAG, _symbol);  
    }
    
    
     /**
    * @notice Returns bool after checking the min max and zero condition
    * @param _symbol - pool id of the asset
    * @param _price - price return by the chainlink
    **/
    function priceCheck(
        bytes32 _symbol,
        uint256 _price
    ) public view returns (bool status) {
        
        if(_price == 0 || _price <= minValue[_symbol] || _price >= maxValue[_symbol] ) {
            return true;
        }
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
            /*uint80 roundID*/,
            int256 answer,
            uint256 startedAt,
            /*uint256 updatedAt*/,
            /*uint80 answeredInRound*/
        ) = 
        AggregatorV3Interface(
            sequencerUptimeFeed
        ).latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) {
            revert SequencerDown(TAG);
        }

        // Make sure the grace period has passed after the
        // sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= GRACE_PERIOD_TIME) {
            revert GracePeriodNotOver(TAG);
        }

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

        if(basePrice <= 0)
            revert ChainlinkMalfunction(TAG, _symbol);

        if(timeStamp == 0)
            revert RoundNotComplete(TAG, _symbol);
        
        if (timeStamp < block.timestamp - heartBeatValue[_symbol])
            revert PriceOutDated(TAG, _symbol);

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
    * @notice Returns price of the asset fetched from price feed maintained
    * @param _symbol - pool id of the asset
    **/
    function getPriceFromPriceFeed(
        bytes32 _symbol
    ) public view returns (uint256 price) {
        price = IPriceFeed(priceFeed).getPrice(_symbol);

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