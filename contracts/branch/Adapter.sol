// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
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
contract AdapterBranch is Initializable, OwnableUpgradeable {
    using SafeMath for uint256;

    address public roleManager;
    address public branch;

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
        require(
            routeExist[router[route]],
            string.concat(TAG, "No route exists")
        );
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
