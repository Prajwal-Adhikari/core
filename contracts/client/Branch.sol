// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../layerZero/lzApp/LzApp.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import './interfaces/IAdapter.sol';

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

contract Branch is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    uint8 internal constant TYPE_DEPOSIT = 1;
    uint8 internal constant TYPE_REPAY = 2;

    uint public constant ROOT_DECIMALS = 18;
    uint public constant BASE = 10 ** ROOT_DECIMALS;
    
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public adapter;

    struct PoolInfo {
        bool enable;
        address token;
    }

    mapping(bytes32 => PoolInfo) public pools;

    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /**
    * @dev only adapter can use functions affected by this modifier
    **/
    modifier onlyAdapter {
        require(adapter == msg.sender, "The caller must be adapter contract");
        _;
    }

    function setPool(bytes32 id, address token, bool enable) external onlyOwner {
        PoolInfo storage pool = pools[id];
        pool.enable = enable;
        pool.token = token;
    }

    /**
    * @dev Configures adapter contract. 
    * This function can only be accessed by the contract owner.
    * @param adapterAddress address of the adapter contract.
    **/
    function setAdapter(address adapterAddress) external onlyOwner {
        adapter = adapterAddress;

    }

    /** 
    * @dev sends a deposit information message to the Root.
    * @param id pool id of the pool of the deposited amount
    * @param amount amount deposited in the pool
    * @param route communication protocol
    **/
    function depositRequest(bytes32 id, uint amount, bytes32 route) external nonReentrant payable {
        require(pools[id].enable, "Pool not enable");
        _pay(pools[id].token, amount, id, TYPE_DEPOSIT, route);
    }

    /** 
    * @dev sends a repay information message to the Root.
    * @param id pool id of the pool of the repaid amount
    * @param amount amount repaid in the pool
    **/
    function repayRequest(bytes32 id, uint amount, bytes32 route) external nonReentrant payable {
        require(pools[id].enable, "Pool not enable");
        _pay(pools[id].token, amount, id, TYPE_REPAY, route);
    }

    /**
    * @dev send the deposited / repaid amount from user to the pool.
    * Called when contract receives deposit / repay request from an address.
    * @param token token address of the deposited / repaid token
    * @param amount amount of token deposited / repaid
    * @param id pool id of the pool 
    * @param functionType type of function
    **/
    function _pay(address token, uint amount, bytes32 id, uint8 functionType, bytes32 route) internal {
        (uint64 amountpx, uint64 amountsx) = _buildRemoteAmount(amount, id);
        bytes memory payload = abi.encodePacked(functionType, id, addressToBytes32(msg.sender), amountpx, amountsx);
        if(token == address(0)) {
            require(msg.value >= amount, "Invalid amount");
            IAdapter(adapter).send{value: msg.value.sub(amount)}(payload, msg.sender, msg.value.sub(amount), route);
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            IAdapter(adapter).send{value: msg.value}(payload, msg.sender, msg.value, route);
        }
    }

    /**
    * @dev get the withdrawn / borrowed amount from the pool to `to`.
    * Called when contract receives borrow / withdraw request from Root.
    * @param id token address of the withdrawn / borrowed token
    * @param amount amount of token withdrawn / borrowed
    * @param to receiver address
    **/
    function get(bytes32 id, uint amount, address to) external onlyAdapter {
        address token = pools[id].token;
        if(token == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        
    }
    

    function addressToBytes32(address addr) public pure returns (bytes32) {
        bytes32 result;
        assembly {
            mstore(0, addr)
            result := mload(0)
        }
        return result;
    }

    function _buildRemoteAmount(uint _localAmount, bytes32 _id) view internal returns (uint64 amountpx, uint64 amountsx) {
        (, bytes memory data) = pools[_id].token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        uint8 decimal = abi.decode(data, (uint8));
        _localAmount = decimal > ROOT_DECIMALS ? _localAmount / (10 ** (decimal - ROOT_DECIMALS)): _localAmount * (10 ** (ROOT_DECIMALS - decimal));
        amountpx = uint64(_localAmount / BASE);
        amountsx = uint64(_localAmount % BASE);
    }

}