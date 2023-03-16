// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../layerZero/lzApp/LzApp.sol";

import './interfaces/ICEToken.sol';
import './interfaces/IDebtToken.sol';
import './interfaces/IOracle.sol';
import './libraries/Data.sol';
import './FeeProvider.sol';

/** 
* Title Root
* Root is deployed on a single chain where all the global data is stored. 
* All the Branches are connected to Root, all of which sends deposit and repay information
* to Root.
* Most of the lending and borrowing logic like interest rate calculation, checks, etc. is in Root.
* Users interact with Root for Borrow, Withdraw, and Liquidate actions.
**/
contract Pool is Ownable, ReentrancyGuard, LzApp {
    using SafeMath for uint256;

    IOracle public oracle;
    address public treasury;
    address public cedroToken;
    address public feeProvider;

    bool public feeEnable;
    bool public rewardEnable;

    uint8 internal constant TYPE_DEPOSIT = 1;
    uint8 internal constant TYPE_REPAY = 2;

    uint constant public MAX_HEALTH_FACTOR = 1e18;
    uint constant public YEAR = 365 * 86400;
    mapping(bytes32 => Data.ReserveData) public reserves;
    mapping(bytes32 => Data.ConfigData) public configs;
    mapping(uint16 => mapping(bytes32 => uint)) public chains;
    mapping(address => bytes32[]) public users;

    uint public GAS_USAGE = 200000;

    constructor(address _lzEndpoint, address _treasury, uint16 _localChainId) LzApp(_lzEndpoint, _localChainId) {
        treasury = _treasury;
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
    * @dev Registers a new pool in the protocol. 
    * This function can only be accessed by the contract owner.
    * @param id id of the pool to be created
    * @param config a ConfigData struct containing the interest rate and liqudation variables.
    * @param _ceToken address to the ceToken smart contract for this pool.
    * @param _debtToken address to the debtToken smart contract for this pool.
    **/
    function initPool(bytes32 id, Data.ConfigData memory config, address _ceToken, address _debtToken) external onlyOwner {
        updateInterestRate(id);
        configs[id] = config;
        Data.ReserveData storage reserve = reserves[id];
        reserve.ceToken = _ceToken;
        reserve.debtToken = _debtToken;
        reserve.ceScaled = 1e18;
        reserve.dtScaled = 1e18;
    }

    /**
    * @dev Freezes/Unfreezes a pool with pool id `id`.
    * This function is only accessible by the contract owner and can be used in extreme cases.
    * @param id id of the pool to freeze/unfreeze
    * @param enable bool to freeze/unfreeze
    **/
    function changePoolStatus(bytes32 id, bool enable) external onlyOwner {
        reserves[id].enable = enable;
        emit Data.ChangePoolStatus(id, enable);
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

    function refresh(bytes32 id) internal {
        Data.ReserveData storage reserve = reserves[id];
        if(reserve.ceSupply > 0) {
            uint increasedDebt = block.timestamp.sub(reserve.lastUpdateTime).mul(reserve.interestRate).div(YEAR);
            reserve.dtScaled = reserve.dtScaled.add(increasedDebt);

            uint increasedAPY = increasedDebt.mul(reserve.debtSupply).div(1e18);
            uint tokenAmountTreasury = increasedAPY.mul(configs[id].tsuPercent).div(1e18);
            reserve.ceScaled = reserve.ceScaled.add(increasedAPY.sub(tokenAmountTreasury).mul(1e18).div(reserve.ceSupply));
            

            uint ceAmountTreasury = tokenAmountTreasury.mul(1e18).div(reserve.ceScaled);
            ICEToken(reserve.ceToken).mint(treasury, ceAmountTreasury);
            reserve.ceSupply = reserve.ceSupply.add(ceAmountTreasury);
            emit Data.MintToTreasury(id, tokenAmountTreasury, ceAmountTreasury);
        }
        reserve.lastUpdateTime = block.timestamp;
         
        // _;
    }

    function setOracle(IOracle _oracle) external onlyOwner {
        oracle = _oracle;
    }

    function updateInterestRate(bytes32 id) internal {
        Data.ReserveData storage reserve = reserves[id];
        Data.ConfigData memory config = configs[id];
        if(reserve.debtSupply > 0) {
            
            uint totalDeposit = reserve.ceSupply.mul(reserve.ceScaled).div(1e18);
            uint totalBorrow = reserve.debtSupply.mul(reserve.dtScaled).div(1e18);
            uint currentRatio = totalBorrow.mul(1e18).div(totalDeposit);

            if(currentRatio <= config.bestRatio) {
                //Rt = R0 + (Ut / Ub) * Rslope1
                reserve.interestRate = config.baseRate.add(currentRatio.mul(config.slope1).div(config.bestRatio));
            } else {
                uint one = 1e18;
                //Rt = R0 + Rslope1 + (Ut - Ub) / (1 - Ub) * Rslope2
                reserve.interestRate = config.baseRate.add(config.slope1).add(currentRatio.sub(config.bestRatio).mul(config.slope2).div(one.sub(config.bestRatio)));
            }
            reserve.currentRatio = currentRatio;
        }
        
    }

    function addToken(address user, bytes32 id) internal {
        for(uint i = 0;i < users[user].length;i++) {
            if(users[user][i] == id) {
                return;
            }
        }
        users[user].push(id);
    }

    /** 
    * @dev returns the health factor of the address `user`. 
    * @param user wallet address for which the health factor is calculated.
    **/
    function healthFactor(address user) public view returns(Data.HealthData memory health) {
        bytes32[] memory ids = users[user];
        if(ids.length > 0) {
            uint[] memory prices = oracle.getPrices(ids);
            for(uint i = 0;i < ids.length;i++) {
                (uint collateralValue, uint debtValue) = _getValues(user, prices[i], ids[i]);
                health.collateralValue = health.collateralValue.add(collateralValue);
                health.debtValue = health.debtValue.add(debtValue);
                health.ltsValue = health.ltsValue.add(collateralValue.mul(configs[ids[i]].lts).div(1e18));
            }

            if(health.ltsValue > 0) {
                health.factor = health.debtValue.mul(1e18).div(health.ltsValue);
            }
        }
    }

    function _getValues(address user, uint price, bytes32 id) internal view returns(uint collateralValue, uint debtValue) {
        Data.ReserveData memory reserve = reserves[id];
        address _user = user;

        uint increasedDebt = block.timestamp.sub(reserve.lastUpdateTime).mul(reserve.interestRate).div(YEAR);
        uint dtScaled = reserve.dtScaled.add(increasedDebt);
        uint ceScaled = reserve.ceScaled.add(increasedDebt.mul(reserve.currentRatio).div(1e18).mul(1e18 - configs[id].tsuPercent).div(1e18));
        collateralValue = IERC20(reserve.ceToken).balanceOf(_user).mul(ceScaled).div(1e18).mul(price).div(1e18);
        debtValue = IERC20(reserve.debtToken).balanceOf(_user).mul(dtScaled).div(1e18).mul(price).div(1e18);
    }
    
    function _bytes32ToAddress(bytes32 _bytes) pure internal returns (address addr){
        addr = address(uint160(uint256(_bytes)));
    }


    function checkHealth(address user) view public {
        require(healthFactor(user).factor < MAX_HEALTH_FACTOR, "Health failed");
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
        refresh(id);
        Data.ReserveData storage reserve = reserves[id];
        require(reserve.enable, "Not enable now");

        uint tokenAmount = reserve.ceScaled.mul(ceAmount).div(1e18);
        require(chains[chainId][id] >= tokenAmount, "No enough liquidity");
        ICEToken(reserve.ceToken).burn(msg.sender, ceAmount);
        reserve.ceSupply = reserve.ceSupply.sub(ceAmount);
        chains[chainId][id] -= tokenAmount;
        updateInterestRate(id);

        if(feeEnable){
        uint fee = FeeProvider(feeProvider).getFeeAmount(chainId, id);
        tokenAmount -= fee;
        }

        checkHealth(msg.sender);
        _sendToken(id, chainId, to, tokenAmount);
        emit Data.Withdraw(msg.sender, _bytes32ToAddress(to), id, chainId, tokenAmount, ceAmount);
    }

    // avoid stack too deep error
    function _buildBorrowParams(bytes32 id, uint16 chainId, uint tokenAmount) view internal returns(Data.BorrowParams memory params)  {
        Data.ReserveData memory reserve = reserves[id];
        Data.ConfigData memory config = configs[id];
        params.liquidity = chains[chainId][id];
        params.debtAmount = tokenAmount.mul(1e18).div(reserve.dtScaled);
        params.price = oracle.getSinglePrice(id).div(1e18);
        params.ltv = config.ltv;
        params.debtToken = reserve.debtToken;
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
        refresh(id);
        Data.BorrowParams memory params = _buildBorrowParams(id, chainId, tokenAmount);    

        require(params.liquidity >= tokenAmount, "No enough liquidity");
        IDebtToken(params.debtToken).mint(msg.sender, params.debtAmount);
        reserves[id].debtSupply += params.debtAmount;
        updateInterestRate(id);
        addToken(msg.sender, id);
        chains[chainId][id] -= tokenAmount;
        
        Data.HealthData memory healthData = healthFactor(msg.sender);
        require(healthData.collateralValue.mul(params.ltv).div(1e18) >= healthData.debtValue.add(tokenAmount.mul(params.price).div(1e18)), "LTV check failed");

        if(feeEnable){
        uint fee = FeeProvider(feeProvider).getFeeAmount(chainId, id);
        tokenAmount -= fee;
        }

        _sendToken(id, chainId, to, tokenAmount);
        emit Data.Borrow(msg.sender, _bytes32ToAddress(to), id, chainId, tokenAmount, params.debtAmount);
    }

    // caluculate liquidate info and avoid stack too deep error
    function _buildLiquidateParams(bytes32 collateralId, bytes32 debtId, uint debtAmount) view internal returns(Data.LiquidateParams memory params) {
        Data.ReserveData memory debtReserve = reserves[debtId];
        params.debtValue = debtAmount.mul(debtReserve.dtScaled).div(1e18);
        params.ceDebtAmount = params.debtValue.mul(1e18).div(debtReserve.ceScaled);
 
        uint collateralValue = params.debtValue.mul(1e18).div(oracle.getSinglePrice(collateralId));
        params.ceCollateralAmount = collateralValue.add(collateralValue.mul(configs[collateralId].ltBonus).div(1e18));
    }
    /**
    * @dev liquidates the position of address `user`.
    * @param user the address whose position is to be liquidated
    * @param collateralId the pool id of the collateral asset
    * @param debtId the pool id of the debt asset
    * @param debtAmount total debt amount of user
    **/
    function liquidate(address user, bytes32 collateralId, bytes32 debtId, uint debtAmount) external nonReentrant {
        require(user != msg.sender, "Same address");
        refresh(collateralId);
        refresh(debtId);
        Data.HealthData memory healthData = healthFactor(user);
        require(healthData.factor >= MAX_HEALTH_FACTOR, "Cannot liquidate now");
        Data.ReserveData storage debtReserve = reserves[debtId];
        Data.ReserveData memory collateralReserve = reserves[collateralId];
        Data.LiquidateParams memory params = _buildLiquidateParams(collateralId, debtId, debtAmount);
        
        IDebtToken(debtReserve.debtToken).burn(user, debtAmount);
        IDebtToken(debtReserve.ceToken).burn(msg.sender, params.ceDebtAmount);

        debtReserve.debtSupply = debtReserve.debtSupply.sub(debtAmount);
        debtReserve.ceSupply = debtReserve.ceSupply.sub(params.ceDebtAmount);
        
        IDebtToken(collateralReserve.ceToken).burn(user, params.ceCollateralAmount);
        IDebtToken(collateralReserve.ceToken).mint(msg.sender, params.ceCollateralAmount);
        
        updateInterestRate(collateralId);
        updateInterestRate(debtId);
        emit Data.Liquidate(user, msg.sender, debtId, collateralId, debtAmount, params.ceDebtAmount, params.ceCollateralAmount);
    }

    // calculate repay info and avoid stack too deep error
    function _buildRepayParams(Data.ReserveData memory reserve, address user, uint tokenAmount) view internal returns(Data.RepayParams memory params) {
        params.ceToken = reserve.ceToken;
        params.debtToken = reserve.debtToken;
        params.dtScaled = reserve.dtScaled;
        params.ceScaled = reserve.ceScaled;
        params.debtAmount = IDebtToken(params.debtToken).balanceOf(user);
        params.repayAmount = params.debtAmount.mul(params.dtScaled).div(1e18);
        params.tokenAmount = tokenAmount;
        params.user = user;
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
        refresh(id);
        Data.RepayParams memory params = _buildRepayParams(reserves[id], user, tokenAmount);
        Data.ReserveData storage reserve = reserves[id];
        uint ceAmount = 0;  
        if(params.tokenAmount >= params.repayAmount) {
            ceAmount = params.tokenAmount.sub(params.repayAmount).mul(1e18).div(params.ceScaled);
            if(ceAmount > 0) {
                ICEToken(params.ceToken).mint(params.user, ceAmount);
                reserve.ceSupply = reserve.ceSupply.add(ceAmount);
            }
        } else {
            params.repayAmount = params.tokenAmount;
            params.debtAmount = params.repayAmount.mul(1e18).div(params.dtScaled);
        }
        
        if(rewardEnable){
        uint reward = FeeProvider(feeProvider).getFeeAmount(chainId, id);
        IERC20(cedroToken).transfer(user, reward);
        }

        chains[chainId][id] += tokenAmount;
        IDebtToken(params.debtToken).burn(params.user, params.debtAmount);
        reserve.debtSupply -= params.debtAmount;
        updateInterestRate(id);

        emit Data.Repay(user, id, chainId, params.repayAmount, params.debtAmount, ceAmount);
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
        refresh(id);
        Data.ReserveData storage reserve = reserves[id];
        require(reserve.enable, "Not enable now");

        uint ceAmount = tokenAmount.mul(1e18).div(reserve.ceScaled);
        ICEToken(reserve.ceToken).mint(user, ceAmount);
        reserve.ceSupply = reserve.ceSupply.add(ceAmount);

        if(rewardEnable){
        uint reward = FeeProvider(feeProvider).getFeeAmount(chainId, id);
        IERC20(cedroToken).transfer(user, reward);
        }
        chains[chainId][id] += tokenAmount;
        updateInterestRate(id);

        addToken(user, id);
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

    /**
    * @dev Returns liquidity of an asset for a chain
    * @param _chainId id of the chain.
    * @param _poolId id of the pool.
    **/
    function getLiquidity( uint16 _chainId, bytes32 _poolId) public view returns (uint){
       return chains[_chainId][_poolId];
    }
}
