// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
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
contract AdapterPool is Initializable, OwnableUpgradeable {
    using SafeMath for uint256;

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
    

    function initialize() public initializer {
        __Ownable_init();
    }

    function setRoleManager(address roleManagerAddress) external onlyOwner {
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
        bytes32 route
    ) external payable onlyRole(IRoleManager(roleManager).POOL()) {
        require(routeExist[router[route]], string.concat(TAG,": No route exists"));
        IRoute(router[route]).send{value: msg.value}(
            payload,
            chainId,
            sender,
            airdropAmount
        );
    }

    function execute(
        bytes memory payload,
        bytes32 chainId
       
    ) external onlyRole(IRoleManager(roleManager).ROUTE()){
         IPool(pool).execute(payload, chainId);

    }
}
