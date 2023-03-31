// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import './interfaces/ICEToken.sol';
import './interfaces/IDebtToken.sol';
import './interfaces/IOracle.sol';
import './libraries/Data.sol';

/** 
* Title Root
* Root is deployed on a single chain where all the global data is stored. 
* All the Branches are connected to Root, all of which sends deposit and repay information
* to Root.
* Most of the lending and borrowing logic like interest rate calculation, checks, etc. is in Root.
* Users interact with Root for Borrow, Withdraw, and Liquidate actions.
**/
contract Core is Initializable, OwnableUpgradeable {
    using SafeMath for uint256;

    uint constant public MAX_HEALTH_FACTOR = 1e18;

    address public treasury; 

    IOracle public oracle;
    address public pool;
    address public liquidationManager;

    uint constant public YEAR = 365 * 86400;
    mapping(bytes32 => Data.ReserveData) public reserves;
    mapping(bytes32 => Data.ConfigData) public configs;
    mapping(uint16 => mapping(bytes32 => uint)) public chains;
    mapping(bytes32 => uint) public totalLiquidity;
    mapping(address => bytes32[]) public users;


    /**
    * @dev only pool can use functions affected by this modifier
    **/
    modifier onlyPool {
        require(pool == msg.sender, "The caller must be a pool contract");
        _;
    }

    /**
    * @dev only liquidation manager can use functions affected by this modifier
    **/
    modifier onlyLiquidationManager {
        require(liquidationManager == msg.sender, "The caller must be a liquidation manager contract");
        _;
    }
    

    function initialize(address _treasury) public initializer {
        treasury = _treasury;
        __Ownable_init();
        
    }

    /**
    * @dev Configures core contract. 
    * This function can only be accessed by the contract owner.
    * @param _poolAddress address of the fee provider contract.
    **/
    function setPool(address _poolAddress) external onlyOwner {
        pool = _poolAddress;

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


    function updateInterestRate(bytes32 id) public {
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

    function refresh(bytes32 id) public {
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
                health.ltsValue = health.ltsValue.add(collateralValue.mul(configs[ids[i]].liqThreshold).div(1e18));
            }

            if(health.ltsValue > 0) {
                health.factor = health.debtValue.mul(1e18).div(health.ltsValue);
            }
        }
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
    function deposit(bytes32 id, uint16 chainId, address user, uint tokenAmount) external onlyPool returns (uint) {
        refresh(id);
        Data.ReserveData storage reserve = reserves[id];
        require(reserve.enable, "Not enable now");

        uint ceAmount = tokenAmount.mul(1e18).div(reserve.ceScaled);
        ICEToken(reserve.ceToken).mint(user, ceAmount);
        reserve.ceSupply = reserve.ceSupply.add(ceAmount);
        chains[chainId][id] += tokenAmount;
        totalLiquidity[id] += tokenAmount;
        updateInterestRate(id);
        addToken(user, id);

        return ceAmount;
    }
/** 
    * @dev sends a withdraw request of amount `ceAmount` to address `to` from pool with pool id `id`
    * in chain with chain id `chainId`.
    * @param id pool id of pool to withdraw from
    * @param chainId chain id of chain to withdraw from
    * @param ceAmount amount to withdraw
    **/
    function withdraw(bytes32 id, uint16 chainId, uint ceAmount, address user) external onlyPool returns (uint) {
        refresh(id);
        Data.ReserveData storage reserve = reserves[id];
        require(reserve.enable, "Not enable now");

        uint tokenAmount = reserve.ceScaled.mul(ceAmount).div(1e18);
        require(chains[chainId][id] >= tokenAmount, "No enough liquidity");
        ICEToken(reserve.ceToken).burn(user, ceAmount);
        reserve.ceSupply = reserve.ceSupply.sub(ceAmount);
        chains[chainId][id] -= tokenAmount;
        totalLiquidity[id] -= tokenAmount;
        updateInterestRate(id);
        checkHealth(user);
        return (tokenAmount);
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

    function borrow(bytes32 id, uint16 chainId, uint tokenAmount, address user) external onlyPool returns (uint) {
        refresh(id);
        Data.BorrowParams memory params = _buildBorrowParams(id, chainId, tokenAmount);    

        require(params.liquidity >= tokenAmount, "No enough liquidity");
        IDebtToken(params.debtToken).mint(user, params.debtAmount);
        reserves[id].debtSupply += params.debtAmount;
        updateInterestRate(id);
        chains[chainId][id] -= tokenAmount;
        totalLiquidity[id] -= tokenAmount;
        
        Data.HealthData memory healthData = healthFactor(user);
        require(healthData.collateralValue.mul(params.ltv).div(1e18) >= healthData.debtValue.add(tokenAmount.mul(params.price).div(1e18)), "LTV check failed");
        return params.debtAmount;
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
    function repay(bytes32 id, uint16 chainId, address user, uint tokenAmount) external onlyPool returns (uint, uint, uint) {
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
        chains[chainId][id] += tokenAmount;
        totalLiquidity[id] += tokenAmount;
        IDebtToken(params.debtToken).burn(params.user, params.debtAmount);
        reserve.debtSupply -= params.debtAmount;
        updateInterestRate(id);
        return (params.repayAmount, params.debtAmount, ceAmount);
    }

    function updateCeAndDebtSupply(bytes32 id, uint ceAmount, uint debtAmount) external onlyLiquidationManager {
        reserves[id].ceSupply = ceAmount;
        reserves[id].debtSupply = debtAmount;
    }

    function checkHealth(address user) view public {
        require(healthFactor(user).factor < MAX_HEALTH_FACTOR, "Health failed");
    }

    function addToken(address user, bytes32 id) internal {
        for(uint i = 0;i < users[user].length;i++) {
            if(users[user][i] == id) {
                return;
            }
        }
        users[user].push(id);
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

    /**
    * @dev Returns liquidity of an asset for a chain
    * @param _chainId id of the chain.
    * @param _poolId id of the pool.
    **/
    function getLiquidity( uint16 _chainId, bytes32 _poolId) public view returns (uint){
       return chains[_chainId][_poolId];
    }

}