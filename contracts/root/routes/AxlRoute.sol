// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {AxelarExecutable} from "../../axelar/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "../../axelar/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "../../axelar/interfaces/IAxelarGasService.sol";
import "../interfaces/IAdapter.sol";
import "../interfaces/IRoleManager.sol";

string constant TAG = "AxlRoutePool";

contract AxlRoutePool is Initializable, AxelarExecutable, ContextUpgradeable {
    mapping(bytes32 => string) public destChain;
    mapping(bytes32 => string) public destAddress;
    mapping(bytes32 => bytes32) public chainKey;
    mapping(bytes32 => bytes32) public trustedContract;

    address public adapter;
    address public roleManager;
    IAxelarGasService gasService;

    event Executed();

    /**
     * @dev Modifier that checks if caller has a specific role.
     **/
    modifier onlyRole(bytes32 role) {
        IRoleManager(roleManager).checkRole(role, _msgSender());
        _;
    }

    function initialize(
        address _gateway,
        address _gasReceiver,
        address roleManagerAddress
    ) public initializer {
        __AxelarExecutable_init(_gateway);
        gasService = IAxelarGasService(_gasReceiver);
        roleManager = roleManagerAddress;
    }


    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }



    function setAdapter(address adapterAddress) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
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
        trustedContract[keccak256(abi.encodePacked(name))] = keccak256(
            abi.encodePacked(addr)
        );
    }

    function send(
        bytes memory payload,
        bytes32 chainId,
        address sender,
        uint256
    ) external payable onlyRole(IRoleManager(roleManager).ADAPTER()) {
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

    function _execute(
        string calldata sourceChain_,
        string calldata sourceAddress_,
        bytes calldata payload_
    ) internal override {
        bytes32 chain = keccak256(abi.encodePacked(sourceChain_));
        bytes32 addr = keccak256(abi.encodePacked(sourceAddress_));
        require(
            trustedContract[chain] == addr,
            string.concat(TAG, ": Invalid contract")
        );
        bytes memory payload = payload_;
        IAdapter(adapter).execute(payload, chainKey[chain]);
    }
}
