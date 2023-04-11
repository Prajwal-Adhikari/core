// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {AxelarExecutable} from "../axelar/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "../axelar/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "../axelar/interfaces/IAxelarGasService.sol";
import "./interfaces/IAdapter.sol";

contract AxlRouteBranch is AxelarExecutable, Ownable{

    string public destinationChain;
    string public destinationAddress;

    address public adapter;

    uint public constant BASE = 10 ** 18;
    IAxelarGasService gasService;

    constructor(
        address _gateway,
        address _gasReceiver
    ) AxelarExecutable(_gateway) {
        gasService = IAxelarGasService(_gasReceiver);
    }

    event Executed();

    /**
    * @dev only adapter can use functions affected by this modifier
    **/
    modifier onlyAdapter {
        require(adapter == msg.sender, "The caller must be a pool contract");
        _;
    }


    /**
    * @dev Configures adapter contract. 
    * This function can only be accessed by the contract owner.
    * @param adapterAddress address of the adapter contract.
    **/
    function setAdapter(address adapterAddress) external onlyOwner {
        adapter = adapterAddress;

    }

    function send(
        bytes memory payload,
        address sender,
        uint gasValue
    ) external payable onlyAdapter {
        if (gasValue > 0) {
            gasService.payNativeGasForContractCall{value: gasValue}(
                address(this),
                destinationChain,
                destinationAddress,
                payload,
                sender
            );
        }
        gateway.callContract(destinationChain, destinationAddress, payload);
    }

    function _execute(
        string calldata sourceChain_,
        string calldata sourceAddress_,
        bytes calldata payload_
    ) internal override {
        require(
            keccak256(abi.encodePacked(destinationChain)) ==
                keccak256(abi.encodePacked(sourceChain_)) &&
                keccak256(abi.encodePacked(destinationAddress)) ==
                keccak256(abi.encodePacked(sourceAddress_)),
            "Invalid source"
        );
        bytes32 id;
        bytes32 to;
        uint64 amountpx;
        uint64 amountsx;
        bytes memory _payload = payload_;
        assembly {
            id := mload(add(_payload, 32))
            to := mload(add(_payload, 64))
            amountpx := mload(add(_payload, 72))
            amountsx := mload(add(_payload, 80))
        }
        uint amount = uint(amountpx) * BASE + uint(amountsx);
        IAdapter(adapter).get(id, amount, address(uint160(uint256(to))));

        emit Executed();
    }
}
