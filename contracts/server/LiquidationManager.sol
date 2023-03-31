// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import './interfaces/IDebtToken.sol';
import './interfaces/IOracle.sol';
import './interfaces/ICore.sol';
import './libraries/Data.sol';

/** 
* Title Root
* Root is deployed on a single chain where all the global data is stored. 
* All the Branches are connected to Root, all of which sends deposit and repay information
* to Root.
* Most of the lending and borrowing logic like interest rate calculation, checks, etc. is in Root.
* Users interact with Root for Borrow, Withdraw, and Liquidate actions.
**/

contract LiquidationManager is Initializable, OwnableUpgradeable {

     using SafeMath for uint256;

    uint constant public MAX_HEALTH_FACTOR = 1e18;
    address public pool;
    address public core;

    IOracle public oracle;

    /**
    * @dev only pool can use functions affected by this modifier
    **/
    modifier onlyPool {
        require(pool == msg.sender, "The caller must be a pool contract");
        _;
    }

    /**
    * @dev Configures pool contract. 
    * This function can only be accessed by the contract owner.
    * @param _poolAddress address of the fee provider contract.
    **/
    function setPool(address _poolAddress) external onlyOwner {
        pool = _poolAddress;

    }
    /**
    * @dev Configures core contract. 
    * This function can only be accessed by the contract owner.
    * @param _coreAddress address of the fee provider contract.
    **/
    function setCore(address _coreAddress) external onlyOwner {
        core = _coreAddress;

    }

    function setOracle(IOracle _oracle) external onlyOwner {
        oracle = _oracle;
    }

    

    // caluculate liquidate info and avoid stack too deep error
    function _buildLiquidateParams(bytes32 collateralId, bytes32 debtId, uint debtAmount, uint discount) view internal returns(Data.LiquidateParams memory params) {
        Data.ReserveData memory debtReserve = ICore(core).reserves(debtId);
        params.debtValue = debtAmount.mul(debtReserve.dtScaled).div(1e18);
        params.ceDebtAmount = params.debtValue.mul(1e18).div(debtReserve.ceScaled);
 
        uint collateralValue = params.debtValue.mul(1e18).div(oracle.getSinglePrice(collateralId));
        params.ceCollateralAmount = collateralValue.add(collateralValue.mul(discount).div(1e18));
    }

    /**
    * @dev liquidates the position of address `user`.
    * @param user the address whose position is to be liquidated
    * @param collateralId the pool id of the collateral asset
    * @param debtId the pool id of the debt asset
    * @param debtAmount total debt amount of user
    **/
    function liquidate(address user, bytes32 collateralId, bytes32 debtId, uint debtAmount) external onlyPool returns (uint, uint){
        ICore(core).refresh(collateralId);
        ICore(core).refresh(debtId);
        Data.HealthData memory healthData = ICore(core).healthFactor(user);
        Data.ConfigData memory config = ICore(core).configs(collateralId);
        require(healthData.factor >= MAX_HEALTH_FACTOR, "Cannot liquidate now");

        uint currentLTV = healthData.debtValue.mul(1e18).div(healthData.collateralValue);
        uint discount;
        uint liqPercent = 1e18;
        if(currentLTV < 1e18) {
           discount = 1e36 / currentLTV - 999000000000000000;
           if(discount > config.liqMaxDiscount) {
             discount = config.liqMaxDiscount;
           }

           uint p1 = config.liqClosingFac.mul(1e18 - currentLTV).div(1e18 - config.liqThreshold);
           if(currentLTV > config.liqThreshold) {
                liqPercent = p1.add(currentLTV.sub(config.liqThreshold).mul(1e18).div(1e18 - config.liqThreshold));
           } else {
                liqPercent = p1.add(config.liqThreshold.sub(currentLTV).mul(1e18).div(1e18 - config.liqThreshold));
           }

           if(liqPercent > 1e18) {
            liqPercent = 1e18;
           }
        }

        Data.ReserveData memory debtReserve = ICore(core).reserves(debtId);
        Data.ReserveData memory collateralReserve = ICore(core).reserves(collateralId);
        Data.LiquidateParams memory params = _buildLiquidateParams(collateralId, debtId, debtAmount, discount);
        require(healthData.debtValue.mul(liqPercent).div(1e18) <= params.debtValue, "Closing factor exceed");
        
        IDebtToken(debtReserve.debtToken).burn(user, debtAmount);
        IDebtToken(debtReserve.ceToken).burn(msg.sender, params.ceDebtAmount);

        debtReserve.debtSupply = debtReserve.debtSupply.sub(debtAmount);
        debtReserve.ceSupply = debtReserve.ceSupply.sub(params.ceDebtAmount);
        ICore(core).updateCeAndDebtSupply(debtId, debtReserve.ceSupply, debtReserve.debtSupply);
        
        IDebtToken(collateralReserve.ceToken).burn(user, params.ceCollateralAmount);
        IDebtToken(collateralReserve.ceToken).mint(msg.sender, params.ceCollateralAmount);
        
        ICore(core).updateInterestRate(collateralId);
        ICore(core).updateInterestRate(debtId);
        return (params.ceDebtAmount, params.ceCollateralAmount);
    }
}