// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "./interfaces/IRoleManager.sol";

string constant TAG = "PriceFeed";

contract PriceFeed is Initializable, ContextUpgradeable {
    address public roleManager;
    mapping(bytes32 => uint256) public prices;

    event SetPrice(bytes32 symbol, uint256 price);

    error ArrayLengthMismatched(string contractTAG);
    error PriceNotSet(string contractTAG);

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
     * @notice Configures the prices of assets
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _symbols - list of pool ids of the assets
     * @param _prices - prices of the asset
     **/
    function setPrices(
        bytes32[] memory _symbols,
        uint256[] memory _prices
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        if (_symbols.length != _prices.length)
            revert ArrayLengthMismatched(TAG);
        for (uint256 i; i < _symbols.length; i++) {
            prices[_symbols[i]] = _prices[i];
            emit SetPrice(_symbols[i], _prices[i]);
        }
    }

    /**
     * @notice Configures the prices of assets
     * This function can only be accessed by the account with role SET_ORACLE_METHOD.
     * @param _symbol - pool id of the asset
     * @param _price - price of the asset
     **/
    function setPrice(
        bytes32 _symbol,
        uint256 _price
    ) external onlyRole(IRoleManager(roleManager).SET_ORACLE_METHOD()) {
        if (_price <= 0) revert PriceNotSet(TAG);
        prices[_symbol] = _price;
        emit SetPrice(_symbol, _price);
    }

    /**
     * @notice Returns price of assets
     * @param _symbols - list of the asset's pool id
     **/
    function getPrices(
        bytes32[] memory _symbols
    ) external view returns (uint256[] memory results) {
        results = new uint256[](_symbols.length);
        for (uint256 i; i < _symbols.length; i++) {
            uint256 price = prices[_symbols[i]];
            if (price <= 0) revert PriceNotSet(TAG);
            results[i] = price;
        }
    }

    /**
     * @notice Returns price of an asset
     * @param _symbol - pool id of the asset
     **/
    function getPrice(bytes32 _symbol) external view returns (uint256 result) {
        result = prices[_symbol];
        if (result <= 0) revert PriceNotSet(TAG);
    }
}
