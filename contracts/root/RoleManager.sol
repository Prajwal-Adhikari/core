// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

string constant TAG = "RoleManagerPool";

/**
 * @title RoleManagerBranch
 * @notice RoleManager is used to grant roles to EOAs.
 **/
contract RoleManagerPool is Initializable, AccessControlUpgradeable {
    bytes32 public constant SET_POOL_METHOD = keccak256("SET_POOL_METHOD");
    bytes32 public constant SET_CORE_METHOD = keccak256("SET_CORE_METHOD");
    bytes32 public constant SET_ADAPTER_METHOD =
        keccak256("SET_ADAPTER_METHOD");
    bytes32 public constant SET_ROUTE_METHOD = keccak256("SET_ROUTE_METHOD");
    bytes32 public constant SET_LIQUIDATION_METHOD =
        keccak256("SET_LIQUIDATION_METHOD");
    bytes32 public constant SET_FEEPROVIDER_METHOD =
        keccak256("SET_FEEPROVIDER_METHOD");
    bytes32 public constant SET_CE_TOKEN_METHOD =
        keccak256("SET_CE_TOKEN_METHOD");
    bytes32 public constant SET_CONTROLLER_METHOD =
        keccak256("SET_CONTROLLER_METHOD");
        bytes32 public constant SET_ORACLE_METHOD =
        keccak256("SET_ORACLE_METHOD");

    bytes32 public constant INIT_POOL = keccak256("INIT_POOL");
    bytes32 public constant POOL_STATUS = keccak256("POOL_STATUS");
    bytes32 public constant PROTOCOL_PAUSE = keccak256("PROTOCOL_PAUSE");
    bytes32 public constant MINT_BURN_CE_DEBT_TOKEN =
        keccak256("MINT_BURN_CE_DEBT_TOKEN");

    bytes32 public constant POOL = keccak256("POOL");
    bytes32 public constant LIQUIDATION_MANAGER =
        keccak256("LIQUIDATION_MANAGER");
    bytes32 public constant FEE_PROVIDER = keccak256("FEE_PROVIDER");
    bytes32 public constant CORE = keccak256("CORE");
    bytes32 public constant ADAPTER = keccak256("ADAPTER");
    bytes32 public constant ROUTE = keccak256("ROUTE");
    bytes32 public constant CONTROLLER = keccak256("CONTROLLER");

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

    /**
     * @notice Sets new adminRole for a role
     * This function can be called by the account having adminRole for the `role`
     * @param role - particular role 
     * @param adminRole - new role to be assigned as admin
     **/
    function setRoleAdmin(
        bytes32 role,
        bytes32 adminRole
    ) public onlyRole(getRoleAdmin(role)) {
        _setRoleAdmin(role, adminRole);
    }

    /**
     * @notice Checks role for an account
     * Reverts if the account doesnt have permission of the role
     * @param role - role of contract.
     * @param account - address of user.
     **/
    function checkRole(bytes32 role, address account) public view {
        _checkRole(role, account);
    }
}
