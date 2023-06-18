// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import {AxelarExecutable} from "../../communicationProtocol/axelar/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "../../communicationProtocol/axelar/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "../../communicationProtocol/axelar/interfaces/IAxelarGasService.sol";
import "../interfaces/IAdapter.sol";
import "../interfaces/IRoleManager.sol";
import "../libraries/Address.sol";

string constant TAG = "AxlRoutePool";

contract AxlRoutePool is Initializable, AxelarExecutable, ContextUpgradeable {
    mapping(bytes32 => string) public destChain;
    mapping(bytes32 => string) public destAddress;
    mapping(bytes32 => bytes32) public chainKey;
    mapping(bytes32 => address) public trustedContract;

    address public adapter;
    address public roleManager;
    IAxelarGasService gasService;
    bytes32 public route;

    event Executed();

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
        address _gateway,
        address _gasReceiver,
        address roleManagerAddress,
        string calldata _localChain
    ) public initializer {
        __AxelarExecutable_init(_gateway, _localChain);
        gasService = IAxelarGasService(_gasReceiver);
        roleManager = roleManagerAddress;
    }

    function setRoleManager(
        address roleManagerAddress
    ) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    function setAdapter(
        address adapterAddress
    ) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
        adapter = adapterAddress;
    }

    function setDestChainIdNameAddress(
        bytes32 chainId,
        string calldata name,
        string calldata addr
    ) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
        destChain[chainId] = name;
        destAddress[chainId] = addr;
        chainKey[keccak256(abi.encodePacked(name))] = chainId;
        trustedContract[keccak256(abi.encodePacked(name))] = StringToAddress.toAddress(addr);
    }

    function setRoute(
        bytes32 routeKey
    ) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
        route = routeKey;
    }

    function send(
        bytes memory payload,
        bytes32 chainId,
        address sender,
        uint256,
        address
    ) external payable onlyRole(IRoleManager(roleManager).ADAPTER()) {
        if (
            keccak256(abi.encodePacked(localChainId)) ==
            keccak256(abi.encodePacked(destChain[chainId]))
        ) {
            IAxelarGateway(StringToAddress.toAddress(destAddress[chainId]))
                .localReceive(
                    localChainId,
                    AddressToString.toString(address(this)),
                    payload
                );
        } else {
            if (msg.value > 0) {
                gasService.payNativeGasForContractCall{value: msg.value}(
                    address(this),
                    destChain[chainId],
                    destAddress[chainId],
                    payload,
                    sender
                );
            }
            gateway.callContract(destChain[chainId], destAddress[chainId], payload);
        }
        
    }

    function _execute(
        string calldata sourceChain_,
        string calldata sourceAddress_,
        bytes calldata payload_
    ) internal override {
        bytes32 chain = keccak256(abi.encodePacked(sourceChain_));
        address addr = StringToAddress.toAddress(sourceAddress_);
        require(
            trustedContract[chain] == addr,
            string.concat(TAG, ": Invalid contract")
        );
        IAdapter(adapter).execute(payload_, chainKey[chain], route);
    }
}
