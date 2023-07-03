// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/ILayerZeroReceiver.sol";
import "../interfaces/ILayerZeroUserApplicationConfig.sol";
import "../interfaces/ILayerZeroEndpoint.sol";

/*
 * a generic LzReceiver implementation
 */
contract LzApp is Initializable, OwnableUpgradeable, ILayerZeroReceiver {
    ILayerZeroEndpoint public lzEndpoint;
    uint public localId;

    mapping(uint16 => bytes) public trustedRemoteLookup;

    event SetTrustedRemote(uint16 _srcChainId, bytes _srcAddress);

    error InvalidSrcContract(uint contractCode, bytes srcContract);
    error InvalidEndpointCaller(uint contractCode, address srcContract);
    error DstChainIsNotTrusted(uint contractCode, uint16 dstChainID);
    error FeeRefundFailed(uint contractCode);

    function __LzApp_init(address _endpoint, uint16 _localId) internal onlyInitializing {
        lzEndpoint = ILayerZeroEndpoint(_endpoint);
        localId = _localId;
        __Ownable_init();
    }

    function localReceive(uint16 _srcChainId, bytes memory _payload) public virtual override {
        bytes memory trustedRemote = trustedRemoteLookup[_srcChainId];
        bytes memory sender = abi.encodePacked(msg.sender, address(this));

        if(sender.length != trustedRemote.length)
            revert InvalidSrcContract(5, sender);

        if(keccak256(sender) != keccak256(trustedRemote))
            revert InvalidSrcContract(5, sender);

        _blockingLzReceive(_srcChainId, sender, 0, _payload);
    }

    function lzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) public virtual override {
        // lzReceive must be called by the endpoint for security
        if(_msgSender() != address(lzEndpoint))
            revert InvalidEndpointCaller(5, _msgSender());

        bytes memory trustedRemote = trustedRemoteLookup[_srcChainId];
        // if will still block the message pathway from (srcChainId, srcAddress). should not receive message from untrusted remote.
        if(_srcAddress.length != trustedRemote.length)
            revert InvalidSrcContract(5, _srcAddress);

        if(keccak256(_srcAddress) != keccak256(trustedRemote))
            revert InvalidSrcContract(5, _srcAddress);
            
        _blockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    // abstract function - the default behaviour of LayerZero is blocking. See: NonblockingLzApp if you dont need to enforce ordered messaging
    function _blockingLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) internal virtual {
    }

    

    function _lzSend(uint16 _dstChainId, bytes memory _payload, address payable _refundAddress, address _zroPaymentAddress, bytes memory _adapterParams, uint gasValue) internal virtual {
        bytes memory trustedRemote = trustedRemoteLookup[_dstChainId];

        if(trustedRemote.length == 0)
            revert DstChainIsNotTrusted(5, _dstChainId);

        if(_dstChainId == localId) {
            if (gasValue > 0) {
                (bool sent, ) = _refundAddress.call{value: gasValue}("");
                // require(sent, "LzApp: Failed to refund fees");
                if(! sent)
                    revert FeeRefundFailed(5);
            }
            ILayerZeroReceiver(address(bytes20(trustedRemote))).localReceive(_dstChainId, _payload);
        } else {
            lzEndpoint.send{value: gasValue}(_dstChainId, trustedRemote, _payload, _refundAddress, _zroPaymentAddress, _adapterParams);
        }
    }

    function setSendVersion(uint16 _version) external onlyOwner {
        lzEndpoint.setSendVersion(_version);
    }

    function setReceiveVersion(uint16 _version) external onlyOwner {
        lzEndpoint.setReceiveVersion(_version);
    }

    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external onlyOwner {
        lzEndpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }

    // allow owner to set it multiple times.
    function setTrustedRemote(uint16 _srcChainId, bytes calldata _srcAddress) external onlyOwner {
        trustedRemoteLookup[_srcChainId] = _srcAddress;
        emit SetTrustedRemote(_srcChainId, _srcAddress);
    }

    function retry(uint16 _srcChainId, bytes calldata _srcAddress, bytes calldata _payload) external {
        lzEndpoint.retryPayload(_srcChainId, _srcAddress, _payload);
    }

    function payloadStatus(uint16 _srcChainId, bytes calldata _srcAddress) external view  returns (bool){
        return lzEndpoint.hasStoredPayload(_srcChainId, _srcAddress);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}