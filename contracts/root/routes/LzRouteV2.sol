// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {OApp, Origin, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";


import "../../communicationProtocol/layerZero/interfaces/ILayerZeroReceiver.sol";
import "../interfaces/IAdapter.sol";
import "../interfaces/IRoleManager.sol";

string constant TAG = "LzRouteV2Pool";

contract LzRouteV2Pool is OApp {
    address public adapter;
    address public roleManager;
    mapping(bytes32 => uint32) public chainID;
    mapping(uint32 => bytes32) public chainKey;

    uint32 public localChainId;
    bytes32 public route;
    uint128 public executorGas;
    uint128 public executorValue;

    error InvalidSrcContract(string contractTAG, address srcContract);
    error InsufficientGas(string contractTAG);
    error FeeRefundFailed(string contractTAG);

    /**
     * @dev Modifier that checks if caller has a specific role.
     **/
    modifier onlyRole(bytes32 role) {
        IRoleManager(roleManager).checkRole(role, _msgSender());
        _;
    }

    constructor(address _endpoint, address _owner, address _roleManager, uint32 _localChainId, uint128 _gasUsage) OApp(_endpoint, _owner) {
        if(_gasUsage < 200000)
            revert InsufficientGas(TAG);
        executorGas = _gasUsage;
        roleManager = _roleManager;
        localChainId = _localChainId;
    }

    /**
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/
    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    /**
     * @dev Configures adapter contract.
     * This function can only be accessed by account with role SET_ROUTE_METHOD.
     * @param adapterAddress address of the adapter contract.
     **/
    function setAdapter(
        address adapterAddress
    ) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
        adapter = adapterAddress;
    }

    /**
     * @dev Configures gas value.
     * This function can only be accessed by account with role SET_ROUTE_METHOD.
     * @param _gas value of the gas
     * @param _value value of the gas
     **/
    function setExecutorValues(uint128 _gas, uint128 _value) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
        if(_gas < 200000)
            revert InsufficientGas(TAG);
        executorGas = _gas;
        executorValue = _value;
    }

    /**
     * @dev Links chainId with LayerZero V2 chain eid
     * This function can only be accessed by account with role SET_ROUTE_METHOD.
     * @param chainId - protocol specific key for the chain
     * @param id - LayerZero V2 chain eid
     **/
    function setChainKeyID(bytes32 chainId, uint32 id) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
        chainID[chainId] = id;
        chainKey[id] = chainId;
    }

    /**
     * @dev Assigns key to keep track of the communication route chosen
     * This function can only be accessed by account with role SET_ROUTE_METHOD.
     * @param routeKey - protocol specific key for the route
     **/
    function setRoute(
        bytes32 routeKey
    ) external onlyRole(IRoleManager(roleManager).SET_ROUTE_METHOD()) {
        route = routeKey;
    }

    /**
     * @dev Invoke this method locally when src chainId equal to dst chainId bypassing the communication protocol
     * This function can only be accessed by the contract peer
     * @param origin - the source endpoint identifier for V2
     * @param payload - the signed payload is the UA bytes has encoded to be sent
     * @param data - arbitrary data appended by the Executor
     **/
    function localReceive(Origin calldata origin, bytes calldata payload, bytes calldata data) public {
        if(bytes32ToAddress(peers[origin.srcEid]) !=  msg.sender)
            revert InvalidSrcContract(TAG, msg.sender);

        _lzReceive(origin, "", payload, address(0), data);
        
    }

    // Sends a message from the source to destination chain.
    function send(
        bytes memory payload,
        bytes32 chainId,
        address sender,
        uint256 airdropAmount,
        address airdropReceiver
    ) external payable onlyRole(IRoleManager(roleManager).ADAPTER()) {
        if (localChainId == chainID[chainId]){
            if (msg.value > 0) {
                (bool sent, ) = payable(sender).call{value: msg.value}("");
                if(! sent)
                    revert FeeRefundFailed(TAG);
            }
            Origin memory origin = Origin(localChainId, addressToBytes32(address(this)),0);
            ILayerZeroReceiverV2(bytes32ToAddress(peers[localChainId])).localReceive(origin, payload, bytes(""));
            
        } else {
            bytes memory _options = OptionsBuilder.newOptions();
            bytes memory sendMessage = OptionsBuilder.addExecutorLzReceiveOption(
                _options,
                executorGas,
                executorValue
            );

            if (airdropAmount > 0) {
                bytes memory sendMessageWithAirdrop = OptionsBuilder
                    .addExecutorNativeDropOption(
                        sendMessage,
                        uint128(airdropAmount),
                        addressToBytes32(airdropReceiver)
                    );
                _lzSend(
                    chainID[chainId], // Destination chain's endpoint ID.
                    payload, // Encoded message payload being sent.
                    sendMessageWithAirdrop, // Message execution options (e.g., gas to use on destination).
                    MessagingFee(msg.value, 0), // Fee struct containing native gas and ZRO token.
                    payable(sender) // The refund address in case the send call reverts.
                );
            } else {
                _lzSend(
                    chainID[chainId], // Destination chain's endpoint ID.
                    payload, // Encoded message payload being sent.
                    sendMessage, // Message execution options (e.g., gas to use on destination).
                    MessagingFee(msg.value, 0), // Fee struct containing native gas and ZRO token.
                    payable(sender) // The refund address in case the send call reverts.
                );
            }
        }
    }

    function _lzReceive(
        Origin calldata _origin, // struct containing info about the message sender
        bytes32, // global packet identifier
        bytes calldata payload, // encoded message payload being received
        address, // the Executor address.
        bytes calldata // arbitrary data appended by the Executor
    ) internal override {
        IAdapter(adapter).execute(payload, chainKey[_origin.srcEid], route);
    }

    /* @dev Quotes the gas needed to pay for the full omnichain transaction.
     * @return nativeFee Estimated gas fee in native gas.
     * @return lzTokenFee Estimated gas fee in ZRO token.
     */
    function quote(
        uint32 _dstEid, // Destination chain's endpoint ID.
        bytes calldata _payload, // The message to send.
        uint128 airdropAmount,
        address airdropReceiver,
        bool _payInLzToken // boolean for which token to return fee in
    ) public view returns (uint256 nativeFee, uint256 lzTokenFee) {
        bytes memory options = OptionsBuilder.newOptions();
        options = OptionsBuilder.addExecutorLzReceiveOption(
            options,
            executorGas,
            executorValue
        );

        if (airdropAmount > 0) {
            options = OptionsBuilder
                .addExecutorNativeDropOption(
                    options,
                    uint128(airdropAmount),
                    addressToBytes32(airdropReceiver)
                );
        }
        MessagingFee memory fee = _quote(
            _dstEid,
            _payload,
            options,
            _payInLzToken
        );
        return (fee.nativeFee, fee.lzTokenFee);
    }

    function addressToBytes32(address addr) public pure returns (bytes32) {
        bytes32 result;
        assembly {
            mstore(0, addr)
            result := mload(0)
        }
        return result;
    }

    function bytes32ToAddress(bytes32 data) public pure returns (address) {
        return address(uint160(uint256(data)));
    }

}
