// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AxelarExecutable} from "../../axelar/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "../../axelar/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "../../axelar/interfaces/IAxelarGasService.sol";
import "../interfaces/IAdapter.sol";
import "../interfaces/IRoleManager.sol";

string constant TAG = "AxlRouteBranch";

contract AxlRouteBranch is Initializable, OwnableUpgradeable, AxelarExecutable {

    //Axelar's chain id of the chain where root is deployed
    string public rootChainId;
    // Destination contract address
    string public rootAddress;

    address public adapter;
    address public roleManager;

    IAxelarGasService gasService;

    function initialize(
        address _gateway,
        address _gasReceiver
    ) public initializer {
        __AxelarExecutable_init(_gateway);
        __Ownable_init();
        gasService = IAxelarGasService(_gasReceiver);
    }

    event Executed();

    /**
     * @dev Modifier that checks if caller has a specific role.
     **/
    modifier onlyRole(bytes32 role) {
        IRoleManager(roleManager).checkRole(role, _msgSender());
        _;
    }

    function setRoleManager(address roleManagerAddress) external onlyOwner {
        roleManager = roleManagerAddress;
    }

    function setAdapter(address adapterAddress) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
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

    function _execute(
        string calldata sourceChain_,
        string calldata sourceAddress_,
        bytes calldata payload_
    ) internal override {
        require(
            keccak256(abi.encodePacked(rootChainId)) ==
                keccak256(abi.encodePacked(sourceChain_)) &&
                keccak256(abi.encodePacked(rootAddress)) ==
                keccak256(abi.encodePacked(sourceAddress_)),
            string.concat(TAG,"Invalid source")
        );
        IAdapter(adapter).execute(payload_);

        emit Executed();
    }
}
