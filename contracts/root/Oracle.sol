// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "./interfaces/IRoleManager.sol";

interface IERC20 {
    function decimals() external view returns (uint8);
}

string constant TAG = "Oracle";

pragma solidity >=0.6.2;

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

    address public dexRouterAddress;
    address public roleManager;

    event SetPrice(bytes32 symbol, uint256 price);

    /**
     * @dev Modifier that checks if caller has a specific role.
     **/
    modifier onlyRole(bytes32 role) {
        IRoleManager(roleManager).checkRole(role, _msgSender());
        _;
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

    function setDexRouterAddress(
        address _dexRouterAddress
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        dexRouterAddress = _dexRouterAddress;
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
        for (uint256 i = 0; i < _symbols.length; i++) {
            if (fetchFromDex[_symbols[i]]) {
                if (isStableCoin[_symbols[i]]) {
                    price = 1e18;
                } else {
                    price = getPriceFromDex(_symbols[i]);
                }
            } else {
                price = getPriceFromChainlink(_symbols[i]);
            }
            require(price > 0, string.concat(TAG, ": Price not set up"));
            results[i] = price;
        }
    }

    function getSinglePrice(
        bytes32 _symbol
    ) external view returns (uint256 result) {
            if (fetchFromDex[_symbol]) {
                if (isStableCoin[_symbol]) {
                    result = 1e18;
                } else {
                    result = getPriceFromDex(_symbol);
                }
            } else {
                result = getPriceFromChainlink(_symbol);
            }
            require(result > 0, string.concat(TAG, ": Price not set up"));
            
        }
    

    function getPriceFromChainlink(
        bytes32 _symbol
    ) public view returns (uint256) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int256 basePrice,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) =
         AggregatorV3Interface(
            aggregator[_symbol]
        ).latestRoundData();

        uint8 quoteDecimals = AggregatorV3Interface(aggregator[_symbol])
            .decimals();
        uint256 quotePrice = scalePrice(
            uint256(basePrice),
            quoteDecimals,
            ROOT_DECIMALS
        );

        return quotePrice;
    }

    function getPriceFromDex(
        bytes32 _symbol
    ) public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = assetAddress[_symbol];
        path[1] = assetAddress[stableCoinId[_symbol]];
        uint8 baseDecimals = IERC20(path[0]).decimals();
        uint256[] memory amounts = DexRouter(dexRouterAddress).getAmountsOut(
            uint256(10 ** baseDecimals),
            path
        );

        uint8 quoteDecimals = IERC20(path[1]).decimals();
        uint256 quotePrice = scalePrice(
            amounts[1],
            quoteDecimals,
            ROOT_DECIMALS
        );

        return quotePrice;
    }

    function scalePrice(
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
