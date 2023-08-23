// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {LzApp} from "../../communicationProtocol/layerZero/lzApp/LzApp.sol";
import "../interfaces/IAdapter.sol";
import "../interfaces/IRoleManager.sol";


string constant TAG = "LzRoutePool";

/**
 * Title LzRoutePool
 * Uses LayerZero functions for sending and receiving messages
 **/

contract LzRoutePool is Initializable, LzApp {

    address public adapter;
    address public roleManager;
    mapping(bytes32 => uint16) public chainID;
    mapping(uint16 => bytes32) public chainKey;

    uint256 public gasUsage;
    bytes32 public route;

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

    function initialize(
        address _lzEndpoint,
        uint16 _localChainId,
        uint256 _gasUsage,
        address roleManagerAddress
    ) public initializer {
        __LzApp_init(_lzEndpoint, _localChainId);
        gasUsage = _gasUsage;
        roleManager = roleManagerAddress;
    }

   

    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    function setAdapter(address adapterAddress) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
        adapter = adapterAddress;
    }

    function setGasUsage(uint256 _gasUsage) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
        gasUsage = _gasUsage;
    }

    function setChainKeyID(bytes32 chainId, uint16 id) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
        chainID[chainId] = id;
        chainKey[id] = chainId;
    }

    function setRoute(bytes32 routeKey) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
        route = routeKey;
    }

    /**
     * @dev Receive a cross chain message sent from the branch of chain with chain id `_srcChainId`.
     *
     **/
    function _blockingLzReceive(
        uint16 _srcChainId,
        bytes memory,
        uint64,
        bytes memory _payload
    ) internal override {
        IAdapter(adapter).execute(_payload, chainKey[_srcChainId], route);
    }

    function send(
        bytes memory payload,
        bytes32 chainId,
        address sender,
        uint256 airdropAmount,
        address airdropReceiver
    ) external payable onlyRole(IRoleManager(roleManager).ADAPTER()) {
        if (airdropAmount > 0) {
            _lzSend(
                chainID[chainId],
                payload,
                payable(sender),
                address(this),
                abi.encodePacked(uint16(2), gasUsage, airdropAmount, airdropReceiver),
                msg.value
            );
        } else {
            _lzSend(
                chainID[chainId],
                payload,
                payable(sender),
                address(this),
                abi.encodePacked(uint16(1), gasUsage),
                msg.value
            );
        }
    }

    function estimateFees(
        bytes32 chainId,
        uint256 airdropAmount
    ) public view returns (uint256) {
        bytes memory payload = abi.encode("", chainID[chainId], msg.sender, 0);
        uint256 fees;
        if (airdropAmount > 0) {
            (fees, ) = lzEndpoint.estimateFees(
                chainID[chainId],
                address(this),
                payload,
                false,
                abi.encodePacked(uint16(2), gasUsage, airdropAmount, address(0))
            );
        } else {
            (fees, ) = lzEndpoint.estimateFees(
                chainID[chainId],
                address(this),
                payload,
                false,
                abi.encodePacked(uint16(1), gasUsage)
            );
        }

        return fees;
    }

    function _bytesToAddress(bytes32 bys) private pure returns (address addr) {
        return address(uint160(uint256(bys)));
    }
}
