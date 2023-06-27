// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IRoute.sol";
import "./interfaces/IBranch.sol";
import "./interfaces/IRoleManager.sol";

string constant TAG = "Adapter";

/**
 * Title AdapterBranch
 * Branch interact with Adapter pass message through desired route
 * Route interact with Adapter to call methods of Branch.
 **/
contract AdapterBranch is Initializable, ContextUpgradeable {

    address public roleManager;
    address public branch;

    // key: routeId
    // Example routeId = keccak256("LZO") for LayerZero
    // Example routeId = keccak256("AXL") for Axelar
    mapping(bytes32 => address) public router;
    mapping(address => bool) public routeExist;

    error NoRouteExists(uint contractCode, bytes32 route);
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

    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()){
        roleManager = roleManagerAddress;
    }

    function setBranch(
        address branchAddress
    ) external onlyRole(IRoleManager(roleManager).SET_ADAPTER_METHOD()) {
        branch = branchAddress;
    }

    function setRoute(
        bytes32 route,
        address routeAddress
    ) external onlyRole(IRoleManager(roleManager).SET_ADAPTER_METHOD()) {
        routeExist[routeAddress] = true;
        router[route] = routeAddress;
    }

    function send(
        bytes memory payload,
        address sender,
        uint256 airdropAmount,
        bytes32 route
    ) external payable onlyRole(IRoleManager(roleManager).BRANCH()) {
        if(! routeExist[router[route]])
            revert NoRouteExists(2, route);
        IRoute(router[route]).send{value: msg.value}(
            payload,
            sender,
            airdropAmount
        );
    }

    function execute(
        bytes memory payload
    ) external onlyRole(IRoleManager(roleManager).ROUTE()) {
        IBranch(branch).transferToken(payload);
    }
}
