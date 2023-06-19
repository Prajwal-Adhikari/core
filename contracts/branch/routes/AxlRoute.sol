// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AxelarExecutable} from "../../communicationProtocol/axelar/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "../../communicationProtocol/axelar/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "../../communicationProtocol/axelar/interfaces/IAxelarGasService.sol";
import "../interfaces/IAdapter.sol";
import "../interfaces/IRoleManager.sol";
import "../../root/libraries/Address.sol";

// string constant TAG = "AxlRouteBranch";

contract AxlRouteBranch is Initializable, AxelarExecutable, ContextUpgradeable {
    //Axelar's chain id of the chain where root is deployed
    string public rootChainId;
    // Destination contract address
    string public rootAddress;

    address public adapter;
    address public roleManager;

    IAxelarGasService gasService;

    event Executed();
    error InvalidSource();

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

    /**
     * @dev Modifier that checks if caller has a specific role.
     **/
    modifier onlyRole(bytes32 role) {
        IRoleManager(roleManager).checkRole(role, _msgSender());
        _;
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

    function setRootChainNameAddress(
        string calldata name,
        string calldata addr
    ) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
        rootChainId = name;
        rootAddress = addr;
    }

    function send(
        bytes memory payload,
        address sender,
        uint256
    ) external payable onlyRole(IRoleManager(roleManager).ADAPTER()) {
        if (
            keccak256(abi.encodePacked(localChainId)) ==
            keccak256(abi.encodePacked(rootChainId))
        ) {
            if (msg.value > 0) {
                (bool sent, ) = payable(sender).call{value: msg.value}("");
                require(sent, string.concat(TAG, ": Failed to refund fees"));
            }

            IAxelarGateway(StringToAddress.toAddress(rootAddress)).localReceive(
                localChainId,
                AddressToString.toString(address(this)),
                payload
            );
        } else {
            if (msg.value > 0) {
                gasService.payNativeGasForContractCall{value: msg.value}(
                    address(this),
                    rootChainId,
                    rootAddress,
                    payload,
                    sender
                );
            }
            gateway.callContract(rootChainId, rootAddress, payload);
        }
    }

    function _execute(
        string calldata sourceChain_,
        string calldata sourceAddress_,
        bytes calldata payload_
    ) internal override {

        // require(
        //         keccak256(abi.encodePacked(rootChainId)) ==
        //         keccak256(abi.encodePacked(sourceChain_)) &&
        //         StringToAddress.toAddress(rootAddress) ==
        //         StringToAddress.toAddress(sourceAddress_),
        //     string.concat(TAG, "Invalid source")
        // );

        if( 
            keccak256(abi.encodePacked(rootChainId)) !=
            keccak256(abi.encodePacked(sourceChain_)) 
        )
            revert InvalidSource();

        if(
            StringToAddress.toAddress(rootAddress) !=
            StringToAddress.toAddress(sourceAddress_)
        )
            revert InvalidSource();

        IAdapter(adapter).execute(payload_);
        emit Executed();
    }
}
