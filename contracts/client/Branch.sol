// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../layerZero/lzApp/LzApp.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// todo
// 1.decimal
// 2.emergency withdraw\


/** 
* Title Branch
* Branch is deployed on all the chains Cedro supports.
* It hosts the liquidity pools for all the pools listed in Cedro on that chain. 
* All the Branches are connected to Root, all of which sends deposit and repay information
* to Root.
* Users interact with Branch for Deposit and Repay actions.
**/

contract Branch is Initializable, LzApp {
    uint8 internal constant TYPE_DEPOSIT = 1;
    uint8 internal constant TYPE_REPAY = 2;

    uint public GAS_USAGE;
    uint16 public serverChainId;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    address public localServer;

    struct PoolInfo {
        bool enable;
        address token;
    }

    mapping(bytes32 => PoolInfo) public pools;

    function initialize(address _lzEndpoint, uint16 _localChainId, uint16 _serverChainId, uint _gas) public initializer {
        __LzApp_init(_lzEndpoint, _localChainId);
        serverChainId = _serverChainId;
        GAS_USAGE = _gas;
    }

    function setPool(bytes32 id, address token, bool enable) external onlyOwner {
        PoolInfo storage pool = pools[id];
        pool.enable = enable;
        pool.token = token;
    }

    function setGasUsage(uint _usage) external {
        GAS_USAGE = _usage;
    }

    /*
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
        _pay(pools[id].token, amount, id, TYPE_DEPOSIT);
    }

    /** 
    * @dev sends a repay information message to the Root.
    * @param id pool id of the pool of the repaid amount
    * @param amount amount repaid in the pool
    **/
    function repayRequest(bytes32 id, uint amount) external payable {
        require(pools[id].enable, "Pool not enable");
        _pay(pools[id].token, amount, id, TYPE_REPAY);
    }

    /**
    * @dev send the deposited / repaid amount from user to the pool.
    * Called when contract receives deposit / repay request from an address.
    * @param token token address of the deposited / repaid token
    * @param amount amount of token deposited / repaid
    * @param id pool id of the pool 
    * @param functionType type of function
    **/
    function _pay(address token, uint amount, bytes32 id, uint8 functionType) internal {
        bytes memory payload = abi.encode(functionType, id, msg.sender, amount);
        if(token == address(0)) {
            require(msg.value >= amount, "Invalid amount");
            _send(serverChainId, payload, msg.value.sub(amount));
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            _send(serverChainId, payload, msg.value);
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
    function _send(uint16 chainId, bytes memory payload, uint gasValue) internal {
        _lzSend(chainId, payload, payable(msg.sender), address(this), abi.encodePacked(uint16(1), GAS_USAGE), gasValue);
    }

    function _blockingLzReceive(uint16 _srcId, bytes memory, uint64, bytes memory _payload) internal override {
        require(serverChainId == _srcId, "Invalid chainId");
        (bytes32 id, bytes32 to, uint amount) = abi.decode(_payload, (bytes32, bytes32, uint256));
        _receive(pools[id].token, amount, address(uint160(uint256(to))));
    }
}
