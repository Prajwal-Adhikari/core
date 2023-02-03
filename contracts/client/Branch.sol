// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../layerZero/lzApp/NonblockingLzApp.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// todo
// 1.decimal
// 2.emergency withdraw

/** 
* Title Branch
* Branch is deployed on all the chains Cedro supports.
* It hosts the liquidity pools for all the pools listed in Cedro on that chain. 
* All the Branches are connected to Root, all of which sends deposit and repay information
* to Root.
* Users interact with Branch for Deposit and Repay actions.
**/

contract Branch is LzApp {
    uint8 internal constant TYPE_DEPOSIT = 1;
    uint8 internal constant TYPE_REPAY = 2;

    uint public GAS_USAGE = 300000;
    uint16 public serverChainId;
    using SafeERC20 for IERC20;

    struct PoolInfo {
        bool enable;
        address token;
    }

    mapping(bytes32 => PoolInfo) public pools;

    constructor(address _lzEndpoint, uint16 _serverChainId) LzApp(_lzEndpoint) {
        serverChainId = _serverChainId;
    }

    function setPool(bytes32 id, address token, bool enable) external onlyOwner {
        PoolInfo storage pool = pools[id];
        pool.enable = enable;
    }

    function setGasUsage(uint _usage) external {
        GAS_USAGE = _usage;
    }

    /** 
    * @dev encodes the message type and returns the cross chain messaging fee for LayerZero.
    * @param funtionType message type, either deposit or repay information
    **/
    function estimateFees(uint8 functionType) public view returns (uint) {
        bytes memory payload = "";
        if(functionType == TYPE_DEPOSIT) {
            payload = abi.encode(TYPE_DEPOSIT, 1, msg.sender, 1);
        } else if(functionType == TYPE_REPAY) {
            payload = abi.encode(TYPE_REPAY, 1, msg.sender, 1);
        } else {
            revert("Unsupport functionType");
        }

        (uint fees, ) = lzEndpoint.estimateFees(serverChainId, address(this), payload, false, abi.encodePacked(uint16(1), GAS_USAGE));
        return fees;
    }

    /** 
    * @dev sends a deposit information message to the Root.
    * @param id pool id of the pool of the deposited amount
    * @param amount amount deposited in the pool
    **/
    function depositRequest(bytes32 id, uint amount) external payable {
        require(pools[id].enable, "Pool not enable");
        _pay(pools[id].token, amount);
        bytes memory payload = abi.encode(TYPE_DEPOSIT, id, msg.sender, amount);
        _send(serverChainId, payload);
    }

    /** 
    * @dev sends a repay information message to the Root.
    * @param id pool id of the pool of the repaid amount
    * @param amount amount repaid in the pool
    **/
    function repayRequest(bytes32 id, uint amount) external payable {
        require(pools[id].enable, "Pool not enable");
        _pay(pools[id].token, amount);
        bytes memory payload = abi.encode(TYPE_REPAY, id, msg.sender, amount);
        _send(serverChainId, payload);
    }

    /**
    * @dev send the deposited / repaid amount from user to the pool.
    * Called when contract receives deposit / repay request from an address.
    * @param token token address of the deposited / repaid token
    * @param amount amount of token deposited / repaid
    **/
    function _pay(address token, uint amount) internal {
        if(token == address(0)) {
            require(msg.value == amount, "Invalid amount");
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }
    /**
    * @dev send the withdrawn / borrowed amount from the pool to `to`.
    * Called when contract receives borrow / withdraw request from Root.
    * @param token token address of the withdrawn / borrowed token
    * @param amount amount of token withdrawn / borrowed
    * @param to receiver address
    **/
    function _receive(address token, uint amount, address to) internal {
        if(token == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        
    }

    // LayerZero functions
    function _send(uint16 chainId, bytes memory payload) internal {
        _lzSend(chainId, payload, payable(msg.sender), address(this), abi.encodePacked(uint16(1), GAS_USAGE));
    }

    function _blockingLzReceive(uint16, bytes memory, uint64, bytes memory _payload) internal override {
        (bytes32 id, address user, uint amount) = abi.decode(_payload, (bytes32, address, uint256));
        _receive(pools[id].token, amount, user);
    }
}
