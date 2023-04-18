// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../../layerZero/lzApp/LzApp.sol";
import '../interfaces/IAdapter.sol';

/** 
* Title LzRouteBranch
* Uses LayerZero functions for sending and receiving messages
**/
contract LzRouteBranch is Initializable, LzApp {
    using SafeMath for uint256;

    address public adapter;
    uint16 public serverChainId;

    uint8 internal constant TYPE_DEPOSIT = 1;
    uint8 internal constant TYPE_REPAY = 2;

    uint public gasUsage;

    uint constant public BASE = 10 ** 18;


    /**
    * @dev only adapter can use functions affected by this modifier
    **/
    modifier onlyAdapter {
        require(adapter == msg.sender, "The caller must be a pool contract");
        _;
    }


    function initialize(address _lzEndpoint, uint16 _localChainId, uint16 _serverChainId, uint _gasUsage) public initializer {
        __LzApp_init(_lzEndpoint, _localChainId);
        serverChainId = _serverChainId;
        gasUsage = _gasUsage;
    }


    /**
    * @dev Configures adapter contract. 
    * This function can only be accessed by the contract owner.
    * @param adapterAddress address of the adapter contract.
    **/
    function setAdapter(address adapterAddress) external onlyOwner {
        adapter = adapterAddress;

    }

    // LayerZero functions
    function send(bytes memory payload, address sender, uint gasValue) external payable onlyAdapter {
        _lzSend(serverChainId, payload, payable(sender), address(this), abi.encodePacked(uint16(1), gasUsage), gasValue);
    }

    /** 
    * @dev Receive a cross chain message sent from the branch of chain with chain id `_srcChainId`.
    * 
    **/
    function _blockingLzReceive(uint16 _srcId, bytes memory, uint64, bytes memory _payload) internal override {
        require(serverChainId == _srcId, "Invalid chainId");
        bytes32 id;
        bytes32 to;
        uint64 amountpx;
        uint64 amountsx;
        assembly {
            id := mload(add(_payload, 32))
            to := mload(add(_payload, 64))
            amountpx := mload(add(_payload, 72))
            amountsx := mload(add(_payload, 80))
        }
        uint amount = uint(amountpx) * BASE +  uint(amountsx);
        IAdapter(adapter).get(id, amount, address(uint160(uint256(to))));
    }

    /*
    * @dev encodes the message type and returns the cross chain messaging fee for LayerZero.
    * @param funtionType message type, either deposit or repay information
    **/
    function estimateFees(uint8 functionType) public view returns (uint) {
        bytes memory payload = "";
        if(functionType == TYPE_DEPOSIT) {
            payload = abi.encode(TYPE_DEPOSIT, 1, msg.sender, 1, 1);
        } else if(functionType == TYPE_REPAY) {
            payload = abi.encode(TYPE_REPAY, 1, msg.sender, 1, 1);
        } else {
            revert("Unsupport functionType");
        }

        (uint fees, ) = lzEndpoint.estimateFees(serverChainId, address(this), payload, false, abi.encodePacked(uint16(1), gasUsage));
        return fees;
    }
}