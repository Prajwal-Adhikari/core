// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/ICEToken.sol";
import "../interfaces/IRoleManager.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

string constant TAG = "Controller";

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

    function initialize(
        address roleManagerAddress
    ) public initializer {
    
        roleManager = roleManagerAddress;
    }

    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    function addCEToken(address[] memory _ceTokens) external onlyRole(IRoleManager(roleManager).SET_CONTROLLER_METHOD()) {
        for (uint256 i = 0; i < _ceTokens.length; i++) {
            if (!ceTokenExist[_ceTokens[i]]) {
                ceTokens.push(_ceTokens[i]);
                ceTokenExist[_ceTokens[i]] = true;
            }
        }
    }

    function removeCEToken(address _ceToken) external onlyRole(IRoleManager(roleManager).SET_CONTROLLER_METHOD()) {
        address lastElement = ceTokens[ceTokens.length - 1];
        for (uint256 i = 0; i < ceTokens.length; i++) {
            if (ceTokens[i] == _ceToken) {
                ceTokens[i] = lastElement;
                ceTokenExist[_ceToken] = false;
                ceTokens.pop();
                return;
            }
        }
    }

    function cageUser(address user) external onlyRole(IRoleManager(roleManager).SET_CONTROLLER_METHOD()) {
        for (uint256 i = 0; i < ceTokens.length; i++) {
            ICEToken(ceTokens[i]).setTransferBlockRelease(user, 2 ** 256 - 1);
        }
        emit CagedUser(user);
    }

    function releaseCage(address user) external onlyRole(IRoleManager(roleManager).SET_CONTROLLER_METHOD()) {
        for (uint256 i = 0; i < ceTokens.length; i++) {
            ICEToken(ceTokens[i]).setTransferBlockRelease(user, block.number);
        }
        emit ReleaseCage(user);
    }
}
