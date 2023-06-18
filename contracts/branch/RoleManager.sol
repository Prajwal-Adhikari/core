// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

string constant TAG = "RoleManagerBranch";

contract RoleManagerBranch is Initializable, AccessControlUpgradeable {
    bytes32 public constant SET_BRANCH_METHOD = keccak256("SET_BRANCH_METHOD");
    bytes32 public constant SET_ADAPTER_METHOD =
        keccak256("SET_ADAPTER_METHOD");
    bytes32 public constant SET_ROUTE_METHOD = keccak256("SET_ROUTE_METHOD");

    bytes32 public constant SET_POOL = keccak256("SET_POOL");
    bytes32 public constant PROTOCOL_PAUSE = keccak256("PROTOCOL_PAUSE");
    bytes32 public constant EMERGENCY_WITHDRAW =
        keccak256("EMERGENCY_WITHDRAW");
    bytes32 public constant SWAP = keccak256("SWAP");

    bytes32 public constant BRANCH = keccak256("BRANCH");
    bytes32 public constant ADAPTER = keccak256("ADAPTER");
    bytes32 public constant ROUTE = keccak256("ROUTE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();
        // Grant the contract deployer the default admin role: it will be able
        // to grant and revoke any roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setRoleAdmin(
        bytes32 role,
        bytes32 adminRole
    ) public onlyRole(getRoleAdmin(role)) {
        _setRoleAdmin(role, adminRole);
    }

    function checkRole(bytes32 role, address account) public view {
        _checkRole(role, account);
    }
}
