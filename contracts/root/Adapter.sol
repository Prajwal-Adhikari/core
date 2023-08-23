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
 * @title AdapterPool
 * @notice Pool interact with Adapter pass message through desired route
 * @notice Route interact with Adapter to call methods of Branch.
 **/
contract AdapterPool is Initializable, ContextUpgradeable {
    using SafeMathUpgradeable for uint256;

    address public pool;
    address public roleManager;

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
     * @param roleManagerAddress - Role manager address.
     **/
    function initialize(address roleManagerAddress) public initializer {
        roleManager = roleManagerAddress;
    }

    /**
     * @notice Configures role manager.
     * This function can only be accessed by account with role DEFAULT_ADMIN_ROLE
     * @param roleManagerAddress - address of the role manager contract
     **/
    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    /**
     * @notice Configures pool contract.
     * This function can only be accessed by account with role SET_ADAPTER_METHOD.
     * @param _poolAddress - address of the pool contract.
     **/
    function setPool(address _poolAddress) external onlyRole(IRoleManager(roleManager).SET_ADAPTER_METHOD()) {
        pool = _poolAddress;
    }

    /**
     * @notice Configures route.
     * This function can only be accessed by account with role SET_ADAPTER_METHOD.
     * @param route - name of the route
     * @param routeAddress - address of the route contract.
     **/
    function setRoute(bytes32 route, address routeAddress) external onlyRole(IRoleManager(roleManager).SET_ADAPTER_METHOD()) {
        routeExist[routeAddress] = true;
        router[route] = routeAddress;
    }

    /**
     * @notice Sends swap information from adapter to route
     * This function can only be accessed by account with role POOL.
     * @param payload - information containing receipient address, pool id and token amount
     * @param chainId - chain id of the destination chain
     * @param sender - user address
     * @param airdropAmount - amount to be airdropped to destination chain
     * @param airdropReceiver - receiver of the airdrop
     * @param route - communication protocol
     **/
    function send(
        bytes memory payload,
        bytes32 chainId,
        address sender,
        uint256 airdropAmount,
        address airdropReceiver,
        bytes32 route
    ) external payable onlyRole(IRoleManager(roleManager).POOL()) {
        if(! routeExist[router[route]])
            revert NoRouteExists(TAG, route);
        IRoute(router[route]).send{value: msg.value}(
            payload,
            chainId,
            sender,
            airdropAmount,
            airdropReceiver
        );
    }

    /**
     * @notice Sends payload to the pool contract.
     * This function can only be accessed by account with role ROUTE.
     * @param payload - information containing data , pool id and token amount
     * @param chainId - chain id of the source chain
     * @param route - communication protocol through which payload is received
     **/
    function execute(
        bytes memory payload,
        bytes32 chainId,
        bytes32 route
       
    ) external onlyRole(IRoleManager(roleManager).ROUTE()){
         IPool(pool).execute(payload, chainId, route);

    }
}
