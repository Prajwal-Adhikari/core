// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import './interfaces/IRoute.sol';
import './interfaces/IPool.sol';
import 'hardhat/console.sol';

/** 
* Title AdapterPool
* Pool interact with Adapter pass message through desired route
* Route interact with Adapter to call methods of Branch.
**/
contract AdapterPool is Initializable, OwnableUpgradeable {
    using SafeMath for uint256;

    address public pool;

    mapping(bytes32 => address) public router;
    mapping(address => bool) public routeExist;

    /**
    * @dev only pool can use functions affected by this modifier
    **/
    modifier onlyPool {
        require(pool == msg.sender, "The caller must be a pool contract");
        _;
    }

    /**
    * @dev only routes configured can use functions affected by this modifier
    **/
    modifier onlyRoutes {
        require(routeExist[msg.sender], "The caller must be one of the routes");
        _;
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    /**
    * @dev Configures pool contract. 
    * This function can only be accessed by the contract owner.
    * @param _poolAddress address of the pool contract.
    **/
    function setPool(address _poolAddress) external onlyOwner {
        pool = _poolAddress;

    }

    /**
    * @dev Configures route. 
    * This function can only be accessed by the contract owner.
    * @param route name of the route
    * @param routeAddress address of the route contract.
    **/
    function setRoute(bytes32 route, address routeAddress) external onlyOwner {
        routeExist[routeAddress] = true;
        router[route] = routeAddress;
    }

    function sendToken(bytes32 id, bytes32 chainId, bytes32 user, address sender, uint amount, bytes32 route) external payable onlyPool {
        require(routeExist[router[route]], "No route exists");
        IRoute(router[route]).sendToken{value: msg.value}( id, chainId, user, sender, amount); 
       
    }

    function deposit(bytes32 id, bytes32 chainId, address user, uint tokenAmount) external onlyRoutes {
        IPool(pool).deposit(id, chainId, user, tokenAmount);
    }

    function repay(bytes32 id, bytes32 chainId, address user, uint tokenAmount) external onlyRoutes {
        IPool(pool).repay(id, chainId, user, tokenAmount);
    }
}