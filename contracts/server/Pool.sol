// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../layerZero/lzApp/NonblockingLzApp.sol";

import './interfaces/ICEToken.sol';
import './interfaces/IDebtToken.sol';
import './interfaces/IOracle.sol';

library Data {
    using SafeMath for uint256;
    struct ReserveData {
        //current interest rate
        uint interestRate;
        //current borrowRatio
        uint currentRatio;
        //cetoken address
        address ceToken;
        //debt token address
        address debtToken;
        //express 1 ceToken equal to x underlying token
        uint ceScaled;
        //express 1 debtToken equal to x underlying token
        uint dtScaled;
        //last update timestamp
        uint lastUpdateTime;
        // cetoken total supply cache
        uint ceSupply;
        // debt token total supply cache
        uint debtSupply;
        //is enable now
        bool enable;
    }

    struct ConfigData {
        // using to calculate interest rate
        uint bestRatio;
        uint slope1;
        uint slope2;
        uint baseRate;
        //loan to value
        uint ltv;
        //liquidition threshold 
        uint lts;
        //percent to treasury
        uint tsuPercent;
        //liquidity bonus
        uint ltBonus;
    }

    struct HealthData {
        uint collateralValue;
        uint debtValue;
        uint factor;
        uint ltsValue;
    }

    //using to avoid stack too deep
    struct BorrowParams {
        uint liquidity;
        uint tokenAmount;
        uint price;
        uint ltv;
        uint debtAmount;
        address debtToken;
    }

    //using to avoid stack too deep
    struct RepayParams {
        uint debtAmount;
        uint tokenAmount;
        uint repayAmount;
        address ceToken;
        address debtToken;
        uint dtScaled;
        uint ceScaled;
        address user;
    }


    //using to avoid stack too dept 
    struct LiquidateParams {
        uint debtValue;
        uint ceDebtAmount;
        uint collateralValue;
        uint ceCollateralAmount;
    }

    event MintToTreasury(bytes32 id, uint tokenAmount, uint ceAmount);
    event Deposit(address user, bytes32 id, uint16 chainId, uint tokenAmount, uint ceAmount);
    event Withdraw(address user, bytes32 id, uint16 chainId, uint tokenAmount, uint ceAmount);
    event Borrow(address user, bytes32 id, uint16 chainId, uint tokenAmount, uint debtAmount);
    event Repay(address user, bytes32 id, uint16 chainId, uint tokenAmount, uint debtAmount, uint ceAmount);
    event Liquidate(address user, address liquidator, bytes32 debtId, bytes32 collateralId, 
        uint debtAmount, uint ceDebtAmount, uint ceCollateralAmount);
    event ChangePoolStatus(bytes32 id, bool enable);
}

contract Pool is Ownable, ReentrancyGuard, LzApp {
    using SafeMath for uint256;

    IOracle public oracle;
    address public treasury;

    uint8 internal constant TYPE_DEPOSIT = 1;
    uint8 internal constant TYPE_REPAY = 2;

    uint constant public MAX_HEALTH_FACTOR = 1e18;
    uint constant public YEAR = 365 * 86400;
    mapping(bytes32 => Data.ReserveData) public reserves;
    mapping(bytes32 => Data.ConfigData) public configs;
    mapping(uint16 => mapping(bytes32 => uint)) public chains;
    mapping(address => bytes32[]) public users;

    uint public GAS_USAGE = 200000;

    constructor(address _lzEndpoint, address _treasury) LzApp(_lzEndpoint) {
        treasury = _treasury;
    }

    function estimateFees(uint16 chainId) public view returns (uint) {
        bytes memory payload = abi.encode("", chainId, msg.sender, 0);
        (uint fees, ) = lzEndpoint.estimateFees(chainId, address(this), payload, false, abi.encodePacked(uint16(1), GAS_USAGE));
        return fees;
    }

    function initPool(bytes32 id, Data.ConfigData memory config, address _ceToken, address _debtToken) external onlyOwner {
        configs[id] = config;
        Data.ReserveData storage reserve = reserves[id];
        reserve.ceToken = _ceToken;
        reserve.debtToken = _debtToken;
        reserve.ceScaled = 1e18;
        reserve.dtScaled = 1e18;
    }

    function changePoolStatus(bytes32 id, bool enable) external onlyOwner {
        reserves[id].enable = enable;
        emit Data.ChangePoolStatus(id, enable);
    }


    function _blockingLzReceive(uint16 _srcChainId, bytes memory , uint64 , bytes memory _payload) internal override {
        uint8 functionType;
        assembly {
            functionType := mload(add(_payload, 32))
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
            uint second = block.timestamp.sub(reserve.lastUpdateTime);
            uint increasedDebt = second.mul(reserve.interestRate).div(YEAR);
            reserve.dtScaled = reserve.dtScaled.add(increasedDebt);

            uint increasedAPY = increasedDebt.mul(reserve.debtSupply).div(1e18);
            uint tokenAmountTreasury = increasedAPY.mul(configs[id].tsuPercent).div(1e18);
            reserve.ceScaled = reserve.ceScaled.add(increasedAPY.sub(tokenAmountTreasury).mul(1e18).div(reserve.ceSupply));
        
            uint ceAmountTreasury = tokenAmountTreasury.div(reserve.ceScaled);
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
                //Rt = R0 + Rslope1 + (Ut - Ub) / (1 - Ut) * Rslope2
                reserve.interestRate = config.baseRate.add(config.slope1).add(currentRatio.sub(config.bestRatio).mul(config.slope2).div(one.sub(currentRatio)));
            }
            reserve.currentRatio = currentRatio;
        } else {
            reserve.interestRate = 0;
            reserve.currentRatio = 0;
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
        uint second = block.timestamp.sub(reserve.lastUpdateTime);

        uint increasedDebt = second.mul(reserve.interestRate).div(YEAR);
        uint dtScaled = reserve.dtScaled.add(increasedDebt);
        uint ceScaled = reserve.ceScaled.add(increasedDebt.mul(reserve.currentRatio).div(1e18).mul(1e18 - configs[id].tsuPercent).div(1e18));
        collateralValue = IERC20(reserve.ceToken).balanceOf(_user).mul(ceScaled).div(1e18).mul(price).div(1e18);
        debtValue = IERC20(reserve.debtToken).balanceOf(_user).mul(dtScaled).div(1e18).mul(price).div(1e18);
    }


    function checkHealth(address user) view public {
        require(healthFactor(user).factor < MAX_HEALTH_FACTOR, "Health failed");
    }

    function withdraw(bytes32 id, uint16 chainId, uint ceAmount) payable nonReentrant external {
        refresh(id);
        Data.ReserveData storage reserve = reserves[id];
        require(reserve.enable, "Not enable now");

        uint tokenAmount = reserve.ceScaled.mul(ceAmount).div(1e18);
        require(chains[chainId][id] >= tokenAmount, "No enough liquidity");
        ICEToken(reserve.ceToken).burn(msg.sender, ceAmount);
        reserve.ceSupply = reserve.ceSupply.sub(ceAmount);
        chains[chainId][id] -= tokenAmount;
        updateInterestRate(id);

        checkHealth(msg.sender);
        _sendToken(id, chainId, msg.sender, tokenAmount);
        emit Data.Withdraw(msg.sender, id, chainId, tokenAmount, ceAmount);
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


    function borrow(bytes32 id, uint16 chainId, uint tokenAmount) payable nonReentrant external {
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

        _sendToken(id, chainId, msg.sender, tokenAmount);
        emit Data.Borrow(msg.sender, id, chainId, tokenAmount, params.debtAmount);
    }

    // avoid stack too deep error
    function _buildLiquidateParams(bytes32 collateralId, bytes32 debtId, uint debtAmount) view internal returns(Data.LiquidateParams memory params) {
        Data.ReserveData memory debtReserve = reserves[debtId];
        params.debtValue = debtAmount.mul(debtReserve.dtScaled).div(1e18);
        params.ceDebtAmount = params.debtValue.mul(1e18).div(debtReserve.ceScaled);
 
        uint collateralValue = params.debtValue.mul(1e18).div(oracle.getSinglePrice(collateralId));
        params.ceCollateralAmount = collateralValue.add(collateralValue.mul(configs[collateralId].ltBonus).div(1e18));
    }

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
        
        emit Data.Liquidate(user, msg.sender, debtId, collateralId, debtAmount, params.ceDebtAmount, params.ceCollateralAmount);
    }

    // avoid stack too deep error
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

        chains[chainId][id] += tokenAmount;
        IDebtToken(params.debtToken).burn(params.user, params.debtAmount);
        reserve.debtSupply -= params.debtAmount;
        emit Data.Repay(user, id, chainId, params.repayAmount, params.debtAmount, ceAmount);
    }

    function _deposit(bytes32 id, uint16 chainId, address user, uint tokenAmount) internal {
        refresh(id);
        Data.ReserveData storage reserve = reserves[id];
        require(reserve.enable, "Not enable now");

        uint ceAmount = tokenAmount.mul(1e18).div(reserve.ceScaled);
        ICEToken(reserve.ceToken).mint(user, ceAmount);
        reserve.ceSupply = reserve.ceSupply.add(ceAmount);
        chains[chainId][id] += tokenAmount;
        updateInterestRate(id);

        addToken(user, id);
        emit Data.Deposit(user, id, chainId, tokenAmount, ceAmount);
    }

    function _sendToken(bytes32 id, uint16 chainId, address user, uint amount) internal {
        bytes memory payload = abi.encode(id, user, amount);
        _lzSend(chainId, payload, payable(msg.sender), address(0x0), "");
    }
}
