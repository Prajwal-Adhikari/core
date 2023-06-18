// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IRoute.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IRoleManager.sol";

string constant TAG = "AdapterPool";

/**
 * Title AdapterPool
 * Pool interact with Adapter pass message through desired route
 * Route interact with Adapter to call methods of Branch.
 **/
contract AdapterPool is Initializable, ContextUpgradeable {
    using SafeMathUpgradeable for uint256;

    address public pool;
    address public roleManager;

    mapping(bytes32 => address) public router;
    mapping(address => bool) public routeExist;

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

    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    /**
     * @dev Configures pool contract.
     * This function can only be accessed by the contract owner.
     * @param _poolAddress address of the pool contract.
     **/
    function setPool(address _poolAddress) external onlyRole(IRoleManager(roleManager).SET_ADAPTER_METHOD()) {
        pool = _poolAddress;
    }

    /**
     * @dev Configures route.
     * This function can only be accessed by the contract owner.
     * @param route name of the route
     * @param routeAddress address of the route contract.
     **/
    function setRoute(bytes32 route, address routeAddress) external onlyRole(IRoleManager(roleManager).SET_ADAPTER_METHOD()) {
        routeExist[routeAddress] = true;
        router[route] = routeAddress;
    }

    function send(
        bytes memory payload,
        bytes32 chainId,
        address sender,
        uint256 airdropAmount,
        address airdropReceiver,
        bytes32 route
    ) external payable onlyRole(IRoleManager(roleManager).POOL()) {
        require(routeExist[router[route]], string.concat(TAG,": No route exists"));
        IRoute(router[route]).send{value: msg.value}(
            payload,
            chainId,
            sender,
            airdropAmount,
            airdropReceiver
        );
    }

    function execute(
        bytes memory payload,
        bytes32 chainId,
        bytes32 route
       
    ) external onlyRole(IRoleManager(roleManager).ROUTE()){
         IPool(pool).execute(payload, chainId, route);

    }
}
