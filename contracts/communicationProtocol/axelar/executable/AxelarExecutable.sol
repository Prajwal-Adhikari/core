// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import {IAxelarGateway} from "../interfaces/IAxelarGateway.sol";
import {IAxelarExecutable} from "../interfaces/IAxelarExecutable.sol";
import "../../../root/libraries/Address.sol";

string constant TAG = "AxelarExecutable";

contract AxelarExecutable is Initializable, IAxelarExecutable {
    IAxelarGateway public gateway;
    string public localChainId;
    error CallerIsNotTrustedContract(string contractTAG, string sourceAddressReceived);
    
    function __AxelarExecutable_init(
        address gateway_,
        string calldata _localChainId
    ) internal onlyInitializing {
        if (gateway_ == address(0)) revert InvalidAddress(TAG);

        gateway = IAxelarGateway(gateway_);
        localChainId = _localChainId;
    }

    /**
     * @dev Receives a payload for execution.
     * @param sourceChain_ The source chainID.
     * @param sourceAddress_ The source address.
     * @param payload_ The payload sent from source chain.
     **/
    function localReceive(
        string calldata sourceChain_,
        string calldata sourceAddress_,
        bytes calldata payload_
    ) external {
        if(StringToAddress.toAddress(sourceAddress_) !=  msg.sender)
            revert CallerIsNotTrustedContract(TAG, sourceAddress_);

        _execute(sourceChain_, sourceAddress_, payload_);
    }

    /**
     * @dev Receives a payload for execution.
     * @param commandId The source chainID.
     * @param sourceChain The source chainID.
     * @param sourceAddress The source address.
     * @param payload The payload sent from source chain.
     **/
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external {
        bytes32 payloadHash = keccak256(payload);

        if (
            !gateway.validateContractCall(
                commandId,
                sourceChain,
                sourceAddress,
                payloadHash
            )
        ) revert NotApprovedByGateway(TAG);

        _execute(sourceChain, sourceAddress, payload);
    }

    /**
     * @dev Receives a payload for execution.
     * @param commandId The source chainID.
     * @param sourceChain The source chainID.
     * @param sourceAddress The source address.
     * @param payload The payload sent from source chain.
     * @param tokenSymbol The tokenSymbol.
     * @param amount The amount of token.
     **/
    function executeWithToken(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) external {
        bytes32 payloadHash = keccak256(payload);

        if (
            !gateway.validateContractCallAndMint(
                commandId,
                sourceChain,
                sourceAddress,
                payloadHash,
                tokenSymbol,
                amount
            )
        ) revert NotApprovedByGateway(TAG);

        _executeWithToken(
            sourceChain,
            sourceAddress,
            payload,
            tokenSymbol,
            amount
        );
    }

    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal virtual {}

    function _executeWithToken(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}