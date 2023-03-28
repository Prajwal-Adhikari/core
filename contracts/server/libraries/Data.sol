// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

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
        uint liqThreshold;
        //percent to treasury
        uint tsuPercent;
        //liquidity bonus
        uint liqMaxDiscount;
        // liq closing factor
        uint liqClosingFac;
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
    event Withdraw(address user, address to, bytes32 id, uint16 chainId, uint tokenAmount, uint ceAmount);
    event Borrow(address user, address to, bytes32 id, uint16 chainId, uint tokenAmount, uint debtAmount);
    event Repay(address user, bytes32 id, uint16 chainId, uint tokenAmount, uint debtAmount, uint ceAmount);
    event Liquidate(address user, address liquidator, bytes32 debtId, bytes32 collateralId, 
        uint debtAmount, uint ceDebtAmount, uint ceCollateralAmount);
    event ChangePoolStatus(bytes32 id, bool enable);
}