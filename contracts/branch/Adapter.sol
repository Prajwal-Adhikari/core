// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IRoute.sol";
import "./interfaces/IBranch.sol";

/**
 * Title AdapterBranch
 * Branch interact with Adapter pass message through desired route
 * Route interact with Adapter to call methods of Branch.
 **/
contract AdapterBranch is Initializable, OwnableUpgradeable {
    using SafeMath for uint256;

    address public branch;

    mapping(bytes32 => address) public router;
    mapping(address => bool) public routeExist;

    /**
     * @dev only branch can use functions affected by this modifier
     **/
    modifier onlyBranch() {
        require(branch == msg.sender, "The caller must be a branch contract");
        _;
    }

    /**
     * @dev only routes configured can use functions affected by this modifier
     **/
    modifier onlyRoutes() {
        require(routeExist[msg.sender], "The caller must be one of the routes");
        _;
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    /**
     * @dev Configures branch contract.
     * This function can only be accessed by the contract owner.
     * @param _branchAddress address of the branch contract.
     **/
    function setBranch(address _branchAddress) external onlyOwner {
        branch = _branchAddress;
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

    function send(
        bytes memory payload,
        address sender,
        uint airdropAmount,
        bytes32 route
    ) external payable onlyBranch {
        require(routeExist[router[route]], "No route exists");
        IRoute(router[route]).send{value: msg.value}(
            payload,
            sender,
            airdropAmount
        );
    }

    function get(bytes32 id, uint amount, address to) external onlyRoutes {
        IBranch(branch).get(id, amount, to);
    }
}
