// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../layerZero/lzApp/LzApp.sol";
import './interfaces/ICEToken.sol';
import './interfaces/IDebtToken.sol';
import './interfaces/IOracle.sol';
import './interfaces/ICore.sol';
import './interfaces/IFeeProvider.sol';
import './interfaces/ILiquidationManager.sol';
import './libraries/Data.sol';


/** 
* Title Root
* Root is deployed on a single chain where all the global data is stored. 
* All the Branches are connected to Root, all of which sends deposit and repay information
* to Root.
* Most of the lending and borrowing logic like interest rate calculation, checks, etc. is in Root.
* Users interact with Root for Borrow, Withdraw, and Liquidate actions.
**/
contract Pool is Initializable, ReentrancyGuardUpgradeable, LzApp {
    using SafeMath for uint256;

    address public cedroToken;
    address public feeProvider;
    address public liquidationManager;
    address public core;

    bool public feeEnable;
    bool public rewardEnable;

    uint8 internal constant TYPE_DEPOSIT = 1;
    uint8 internal constant TYPE_REPAY = 2;

    uint public GAS_USAGE;

    function initialize(address _lzEndpoint, uint16 _localChainId, uint _gas) public initializer {
        __LzApp_init(_lzEndpoint, _localChainId);
        __ReentrancyGuard_init();
        GAS_USAGE = _gas;
        
       
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
    * @dev Configures fee and reward status. 
    * This function can only be accessed by the contract owner.
    * @param _feeEnable status of the fee.
    * @param _rewardEnable status of the reward.
    **/
    function setFeeRewardStatus(bool _feeEnable, bool _rewardEnable) external onlyOwner {
        feeEnable = _feeEnable;
        rewardEnable = _rewardEnable;

    }

    /** 
    * @dev Returns the estimated transaction fees to send a cross chain message to
    * the destination chain with chain id `chainId`.
    * @param chainId chain id of the destionation chain as specified by LayerZero
    **/
    function estimateFees(uint16 chainId) public view returns (uint) {
        bytes memory payload = abi.encode("", chainId, msg.sender, 0);
        (uint fees, ) = lzEndpoint.estimateFees(chainId, address(this), payload, false, abi.encodePacked(uint16(1), GAS_USAGE));
        return fees;
    }

    /** 
    * @dev Receive a cross chain message sent from the branch of chain with chain id `_srcChainId`.
    * 
    **/
    function _blockingLzReceive(uint16 _srcChainId, bytes memory , uint64 , bytes memory _payload) internal override {
        uint8 functionType;
        assembly {
            functionType := mload(add(_payload, 32))  // get the request type; either deposit or repay.
        }

        if(functionType == TYPE_DEPOSIT) {  
            (, bytes32 tokenId, address user, uint amount) = abi.decode(_payload, (uint8, bytes32, address, uint256));
            _deposit(tokenId, _srcChainId, user, amount);
        } else if(functionType == TYPE_REPAY) { 
            (, bytes32 tokenId, address user, uint amount) = abi.decode(_payload, (uint8, bytes32, address, uint256));
            _repay(tokenId, _srcChainId, user, amount);
        } 
    }
    
    function _bytes32ToAddress(bytes32 _bytes) pure internal returns (address addr){
        addr = address(uint160(uint256(_bytes)));
    }

    
    /** 
    * @dev sends a withdraw request of amount `ceAmount` to address `to` from pool with pool id `id`
    * in chain with chain id `chainId`.
    * @param id pool id of pool to withdraw from
    * @param chainId chain id of chain to withdraw from
    * @param ceAmount amount to withdraw
    * @param to withdraw address
    **/
    function withdraw(bytes32 id, uint16 chainId, uint ceAmount, bytes32 to) payable nonReentrant external {
        uint tokenAmount = ICore(core).withdraw(id, chainId, ceAmount, msg.sender);
        if(feeEnable){
        uint fee = IFeeProvider(feeProvider).getFeeAmount(chainId, id);
        tokenAmount -= fee;
        }
        _sendToken(id, chainId, to, tokenAmount);
        emit Data.Withdraw(msg.sender, _bytes32ToAddress(to), id, chainId, tokenAmount, ceAmount);
    }

    /** 
    * sends a borrow request of amount `tokenAmount` to address `to` from pool with pool id `id`
    * in chain with chain id `chainId`.
    * @param id pool id of pool to borrow from
    * @param chainId chain id of chain to borrow from
    * @param tokenAmount amount to borrow
    * @param to borrow address
    **/
    function borrow(bytes32 id, uint16 chainId, uint tokenAmount, bytes32 to) payable nonReentrant external {
        uint debtAmount = ICore(core).borrow(id, chainId, tokenAmount, msg.sender);
        if(feeEnable){  
        uint fee = IFeeProvider(feeProvider).getFeeAmount(chainId, id);
        tokenAmount -= fee;
        }
        _sendToken(id, chainId, to, tokenAmount);
        emit Data.Borrow(msg.sender, _bytes32ToAddress(to), id, chainId, tokenAmount, debtAmount);
    }

    // /**
    // * @dev liquidates the position of address `user`.
    // * @param user the address whose position is to be liquidated
    // * @param collateralId the pool id of the collateral asset
    // * @param debtId the pool id of the debt asset
    // * @param debtAmount total debt amount of user
    // **/
    function liquidate(address user, bytes32 collateralId, bytes32 debtId, uint debtAmount) external nonReentrant {
        require(user != msg.sender, "Same address");
        (ceDebtAmount, ceCollateralAmount) = ILiquidationManager(liquidationManager).liquidate(user, collateralId, debtId, debtAmount);
        emit Data.Liquidate(user, msg.sender, debtId, collateralId, debtAmount, ceDebtAmount, ceCollateralAmount);
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
    function _repay(bytes32 id, uint16 chainId, address user, uint tokenAmount) internal {
       
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
    function _deposit(bytes32 id, uint16 chainId, address user, uint tokenAmount) internal {
        
        if(rewardEnable){
        uint reward = IFeeProvider(feeProvider).getFeeAmount(chainId, id);
        console.log("reward",reward);
        IERC20(cedroToken).transfer(user, reward);
        }
        uint ceAmount = ICore(core).deposit(id, chainId, user, tokenAmount);
        
        emit Data.Deposit(user, id, chainId, tokenAmount, ceAmount);
    }

    /** 
    * @dev sends a cross chain message to chain with chain id `chainId` to send
    * `amount` to `user` from the pool with pool id `id`
    * @param id pool id of pool to release amount from
    * @param chainId chain id of chain to release the amount from
    * @param amount amount to be released
    * @param user deposit address    **/
    function _sendToken(bytes32 id, uint16 chainId, bytes32 user, uint amount) internal {
        bytes memory payload = abi.encode(id, user, amount);
        _lzSend(chainId, payload, payable(msg.sender), address(0x0), "", msg.value);
    }

  
}
