// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import './interfaces/ICEToken.sol';
import './interfaces/IDebtToken.sol';
import './interfaces/IOracle.sol';
import './interfaces/ICore.sol';
import './interfaces/IFeeProvider.sol';
import './interfaces/IAdapter.sol';
import './libraries/Data.sol';


/** 
* Title Pool
* Pool is deployed on a single chain
* All the Branches are connected to Pool, all of which sends deposit and repay information
* to Pool
* Users interact with Pool for Borrow, Withdraw, and Liquidate actions
**/
contract Pool is Initializable,OwnableUpgradeable,ReentrancyGuardUpgradeable {
    using SafeMath for uint256;

    address public cedroToken;
    address public feeProvider;
    address public liquidationManager;
    address public core;
    address public adapter;

    bool public feeEnable;
    bool public rewardEnable;



    uint constant public BASE = 10 ** 18;

    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /**
    * @dev only adapter can use functions affected by this modifier
    **/
    modifier onlyAdapter {
        require(adapter == msg.sender, "The caller must be a pool contract");
        _;
    }

    /**
    * @dev Sets Cedro contract. 
    * This function can only be accessed by the contract owner.
    * @param _cedroTokenAddress address of the Cedro Token contract.
    **/
    function setCedroToken(address _cedroTokenAddress) external onlyOwner {
        cedroToken = _cedroTokenAddress;

    }

    /**
    * @dev Configures fee provider contract. 
    * This function can only be accessed by the contract owner.
    * @param _feeProviderAddress address of the fee provider contract.
    **/
    function setFeeProvider(address _feeProviderAddress) external onlyOwner {
        feeProvider = _feeProviderAddress;

    }
    /**
    * @dev Configures core contract. 
    * This function can only be accessed by the contract owner.
    * @param _coreAddress address of the fee provider contract.
    **/
    function setCore(address _coreAddress) external onlyOwner {
        core = _coreAddress;

    }

    /**
    * @dev Configures liquidation manager contract. 
    * This function can only be accessed by the contract owner.
    * @param _liquidationManagerAddress address of the fee provider contract.
    **/
    function setLiquidationManager(address _liquidationManagerAddress) external onlyOwner {
        liquidationManager = _liquidationManagerAddress;

    }

    /**
    * @dev Configures pool contract. 
    * This function can only be accessed by the contract owner.
    * @param adapterAddress address of the pool contract.
    **/
    function setAdapter(address adapterAddress) external onlyOwner {
        adapter = adapterAddress;

    }

    /**
    * @dev Configures fee and reward status. 
    * This function can only be accessed by the contract owner.
    * @param _feeEnable status of the fee.
    * @param _rewardEnable status of the reward.
    **/
    function setFeeRewardStatus(bool _feeEnable, bool _rewardEnable) external onlyOwner {
        feeEnable = _feeEnable;
        rewardEnable = _rewardEnable;

    }
    
    function _bytesToAddress(bytes32 bys) private pure returns (address addr) {
        return address(uint160(uint256(bys)));
    }  
    /** 
    * @dev sends a withdraw request of amount `ceAmount` to address `to` from pool with pool id `id`
    * in chain with chain id `chainId`.
    * @param id pool id of pool to withdraw from
    * @param chainId chain id of chain to withdraw from
    * @param ceAmount amount to withdraw
    * @param to withdraw address
    **/
    function withdraw(bytes32 id, bytes32 chainId, uint ceAmount, bytes32 to, bytes32 route) payable nonReentrant external {
        uint tokenAmount = ICore(core).withdraw(id, chainId, ceAmount, msg.sender);
        if(feeEnable){
        uint fee = IFeeProvider(feeProvider).getFeeAmount(chainId, id);
        tokenAmount -= fee;
        }
        IAdapter(adapter).sendToken{value: msg.value}(id, chainId, to, msg.sender, tokenAmount, route);
        emit Data.Withdraw(msg.sender, _bytesToAddress(to), id, chainId, tokenAmount, ceAmount);
    }

    /** 
    * sends a borrow request of amount `tokenAmount` to address `to` from pool with pool id `id`
    * in chain with chain id `chainId`.
    * @param id pool id of pool to borrow from
    * @param chainId chain id of chain to borrow from
    * @param tokenAmount amount to borrow
    * @param to borrow address
    **/
    function borrow(bytes32 id, bytes32 chainId, uint tokenAmount, bytes32 to, bytes32 route) payable nonReentrant external {
        uint debtAmount = ICore(core).borrow(id, chainId, tokenAmount, msg.sender);
        if(feeEnable){  
        uint fee = IFeeProvider(feeProvider).getFeeAmount(chainId, id);
        tokenAmount -= fee;
        }
        IAdapter(adapter).sendToken{value: msg.value}(id, chainId, to, msg.sender, tokenAmount, route);
        emit Data.Borrow(msg.sender, _bytesToAddress(to), id, chainId, tokenAmount, debtAmount);
    }

    /** 
    * @dev updates the global protocol states after receiving repay information
    * of amount `tokenAmount` from address `user` for pool with pool id 'id' from
    * chain with chain id `chainId`.
    * @param id pool id of pool where amount was repaid to
    * @param chainId chain id of chain repaid from
    * @param tokenAmount amount repaid
    * @param user repay address
    **/
    function repay(bytes32 id, bytes32 chainId, address user, uint tokenAmount) external onlyAdapter {
       
        (uint repayAmount, uint debtAmount, uint ceAmount) = ICore(core).repay(id, chainId, user, tokenAmount);
        if(rewardEnable){
        uint reward = IFeeProvider(feeProvider).getFeeAmount(chainId, id);
        IERC20(cedroToken).transfer(user, reward);
        }
        emit Data.Repay(user, id, chainId, repayAmount, debtAmount, ceAmount); 
    }
 
    /** 
    * @dev updates the global protocol states after receiving deposit information
    * of amount `tokenAmount` from address `user` for pool with pool id 'id' from
    * chain with chain id `chainId`.
    * @param id pool id of pool where amount was deposited to
    * @param chainId chain id of chain deposited to
    * @param tokenAmount amount deposited
    * @param user deposit address
    **/
    function deposit(bytes32 id, bytes32 chainId, address user, uint tokenAmount) external onlyAdapter {
        if(rewardEnable){
        uint reward = IFeeProvider(feeProvider).getFeeAmount(chainId, id);
        console.log("reward",reward);
        IERC20(cedroToken).transfer(user, reward);
        }
        uint ceAmount = ICore(core).deposit(id, chainId, user, tokenAmount);
        
        emit Data.Deposit(user, id, chainId, tokenAmount, ceAmount);
    }

  
}
