// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "../interfaces/ICEToken.sol";
import "../interfaces/IRoleManager.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

/**
 * @title Controller
 * @notice Controller is used to store all the CE tokens addresses.
 **/
contract Controller is ContextUpgradeable {
    address public roleManager;
    address[] public ceTokens;
    mapping(address => bool) public ceTokenExist;

    event CagedUser(address indexed user);
    event ReleaseCage(address indexed user);

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
    function initialize(
        address roleManagerAddress
    ) public initializer {
    
        roleManager = roleManagerAddress;
    }

    /**
     * @notice Sets the roleManager address.
     * @param roleManagerAddress - Role manager address.
     **/
    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    /**
     * @notice Adds CE token to the array.
     * @param _ceTokens - Arrays of CE token.
     **/
    function addCEToken(address[] memory _ceTokens) external onlyRole(IRoleManager(roleManager).SET_CONTROLLER_METHOD()) {
        for (uint256 i; i < _ceTokens.length; i++) {
            if (!ceTokenExist[_ceTokens[i]]) {
                ceTokens.push(_ceTokens[i]);
                ceTokenExist[_ceTokens[i]] = true;
            }
        }
    }

    /**
     * @notice Remove CE token from the array.
     * @param _ceToken - Address of CE token.
     **/
    function removeCEToken(address _ceToken) external onlyRole(IRoleManager(roleManager).SET_CONTROLLER_METHOD()) {
        address lastElement = ceTokens[ceTokens.length - 1];
        for (uint256 i; i < ceTokens.length; i++) {
            if (ceTokens[i] == _ceToken) {
                ceTokens[i] = lastElement;
                ceTokenExist[_ceToken] = false;
                ceTokens.pop();
                return;
            }
        }
    }

    /**
     * @notice Delay user's token tranfer.
     * @param user - Address of user.
     **/
    function cageUser(address user) external onlyRole(IRoleManager(roleManager).SET_CONTROLLER_METHOD()) {
        for (uint256 i; i < ceTokens.length; i++) {
            ICEToken(ceTokens[i]).setTransferBlockRelease(user, 2 ** 256 - 1);
        }
        emit CagedUser(user);
    }

    /**
     * @notice Remove the delay on user's token tranfer.
     * @param user - Address of user.
     **/
    function releaseCage(address user) external onlyRole(IRoleManager(roleManager).SET_CONTROLLER_METHOD()) {
        for (uint256 i; i < ceTokens.length; i++) {
            ICEToken(ceTokens[i]).setTransferBlockRelease(user, block.number);
        }
        emit ReleaseCage(user);
    }
}
