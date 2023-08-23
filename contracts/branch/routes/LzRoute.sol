// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {LzApp} from "../../communicationProtocol/layerZero/lzApp/LzApp.sol";
import "../interfaces/IAdapter.sol";
import "../interfaces/IRoleManager.sol";

string constant TAG = "LzRouteBranch";

/**
 * Title LzRouteBranch
 * Uses LayerZero functions for sending and receiving messages
 **/
contract LzRouteBranch is Initializable, LzApp {
    address public adapter;
    address public roleManager;

    //LayerZero's chain id of the chain where root is deployed
    uint16 public rootChainId;

    //Request Types
    uint8 internal constant TYPE_DEPOSIT = 1;
    uint8 internal constant TYPE_REPAY = 2;
    uint8 internal constant TYPE_SWAP = 3;

    uint256 public gasUsage;
    error InvalidChainId(string contractTAG, uint16 chainIdReceived);
    error UnsupportedFunctionType(string contractTAG, uint8 functionType);
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
        uint16 _rootChainId,
        uint256 _gasUsage,
        address roleManagerAddress
    ) public initializer {
        __LzApp_init(_lzEndpoint, _localChainId);
        rootChainId = _rootChainId;
        gasUsage = _gasUsage;
        roleManager = roleManagerAddress;
    }

    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    /**
     * @dev Configures adapter contract.
     * This function can only be accessed by the contract owner.
     * @param adapterAddress address of the adapter contract.
     **/
    function setAdapter(
        address adapterAddress
    ) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
        adapter = adapterAddress;
    }

    

    /**
     * @dev Configures gas value.
     * This function can only be accessed by the contract owner.
     * @param _gasUsage value of the gas
     **/
    function setGasUsage(
        uint256 _gasUsage
    ) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
        gasUsage = _gasUsage;
    }

    // LayerZero functions
    function send(
        bytes memory payload,
        address sender,
        uint256 airdropAmount
    ) external payable onlyRole(IRoleManager(roleManager).ADAPTER()) {
        if (airdropAmount > 0) {
            _lzSend(
                rootChainId,
                payload,
                payable(sender),
                address(this),
                abi.encodePacked(uint16(2), gasUsage, airdropAmount, sender),
                msg.value
            );
        } else {
            _lzSend(
                rootChainId,
                payload,
                payable(sender),
                address(this),
                abi.encodePacked(uint16(1), gasUsage),
                msg.value
            );
        }
    }

    /**
     * @dev Receive a cross chain message sent from the branch of chain with chain id `_srcChainId`.
     *
     **/
    function _blockingLzReceive(
        uint16 _srcId,
        bytes memory,
        uint64,
        bytes memory _payload
    ) internal override {
        if(rootChainId != _srcId)
            revert InvalidChainId(TAG, _srcId);
        IAdapter(adapter).execute(_payload);
    }

    /*
     * @dev encodes the message type and returns the cross chain messaging fee for LayerZero.
     * @param funtionType message type, either deposit or repay information
     **/
    function estimateFees(
        uint8 functionType,
        uint256 airdropAmount
    ) public view returns (uint256) {
        bytes memory payload = "";
        if (functionType == TYPE_DEPOSIT) {
            payload = abi.encode(TYPE_DEPOSIT, 1, msg.sender, 1, 1);
        } else if (functionType == TYPE_REPAY) {
            payload = abi.encode(TYPE_REPAY, 1, msg.sender, 1, 1);
        } else if (functionType == TYPE_SWAP) {
            payload = abi.encode(TYPE_SWAP, 1, msg.sender, 1, 1);
        } else {
            revert UnsupportedFunctionType(TAG, functionType);
        }
        uint256 fees;
        if (airdropAmount > 0) {
            (fees, ) = lzEndpoint.estimateFees(
                rootChainId,
                address(this),
                payload,
                false,
                abi.encodePacked(uint16(2), gasUsage, airdropAmount, address(0))
            );
        } else {
            (fees, ) = lzEndpoint.estimateFees(
                rootChainId,
                address(this),
                payload,
                false,
                abi.encodePacked(uint16(1), gasUsage)
            );
        }
        return fees;
    }
}
