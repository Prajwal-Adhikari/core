// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IRoute.sol";
import "./interfaces/IBranch.sol";
import "./interfaces/IRoleManager.sol";

string constant TAG = "AdapterBranch";

/**
 * @title AdapterBranch
 * @notice Branch interact with Adapter pass message through desired route
 * @notice Route interact with Adapter to call methods of Branch.
 **/
contract AdapterBranch is Initializable, ContextUpgradeable {

    address public roleManager;
    address public branch;

    // key: routeId
    // Example routeId = keccak256("LZO") for LayerZero
    // Example routeId = keccak256("AXL") for Axelar
    mapping(bytes32 => address) public router;
    mapping(address => bool) public routeExist;

    error NoRouteExists(string contractTAG, bytes32 route);
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
     * @notice Sets the roleManager address.
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
    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()){
        roleManager = roleManagerAddress;
    }

    /**
     * @notice Configures branch contract.
     * This function can only be accessed by account with role SET_ADAPTER_METHOD.
     * @param branchAddress - address of the branch contract.
     **/
    function setBranch(
        address branchAddress
    ) external onlyRole(IRoleManager(roleManager).SET_ADAPTER_METHOD()) {
        branch = branchAddress;
    }

    /**
     * @notice Configures route address for corresponding route.
     * This function can only be accessed by account with role SET_ADAPTER_METHOD.
     * @param route - name of the route
     * @param routeAddress - address of the route contract.
     **/
    function setRoute(
        bytes32 route,
        address routeAddress
    ) external onlyRole(IRoleManager(roleManager).SET_ADAPTER_METHOD()) {
        routeExist[routeAddress] = true;
        router[route] = routeAddress;
    }

    /**
     * @notice Sends payload from branch to selected route.
     * This function can only be accessed by account with role BRANCH.
     * @param payload - information to be passed
     * @param sender - address of the user
     * @param airdropAmount - amount to be sent to the destination chain
     * @param route - communication protocol
     **/
    function send(
        bytes memory payload,
        address sender,
        uint256 airdropAmount,
        bytes32 route
    ) external payable onlyRole(IRoleManager(roleManager).BRANCH()) {
        if(! routeExist[router[route]])
            revert NoRouteExists(TAG, route);
        IRoute(router[route]).send{value: msg.value}(
            payload,
            sender,
            airdropAmount
        );
    }

    /**
     * @notice Sends payload from route to branch.
     * This function can only be accessed by account with role ROUTE.
     * @param payload - information of token amount and receipient.
     **/
    function execute(
        bytes memory payload
    ) external onlyRole(IRoleManager(roleManager).ROUTE()) {
        IBranch(branch).transferToken(payload);
    }
}
