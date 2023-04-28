// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

library Data {
    using SafeMath for uint256;
    struct PoolData {
        //current borrow interest rate
        uint256 borrowInterestRate;
        //current utilizationRatio
        uint256 utilizationRatio;
        //cetoken address
        address ceToken;
        //debt token address
        address debtToken;
        //express 1 ceToken equal to x underlying token
        uint256 ceScaled;
        //express 1 debtToken equal to x underlying token
        uint256 dtScaled;
        //last update timestamp
        uint256 lastUpdateTime;
        // cetoken total supply cache
        uint256 ceSupply;
        // debt token total supply cache
        uint256 debtSupply;
        //is enable now
        bool enable;
    }

    struct ConfigData {
        // using to calculate interest rate
        uint256 optimalUtilizationRatio;
        uint256 slope1;
        uint256 slope2;
        uint256 baseRate;
        //loan to value
        uint256 ltv;
        //liquidition threshold 
        uint256 liqThreshold;
        //percent to treasury
        uint256 treasuryPercent;
        //liquidity bonus
        uint256 liqMaxDiscount;
        // liq closing factor
        uint256 liqClosingFac;
    }

    struct HealthData {
        uint256 collateralValue;
        uint256 debtValue;
        uint256 factor;
        uint256 ltsValue;
    }

    //using to avoid stack too deep
    struct BorrowParams {
        uint256 liquidity;
        uint256 tokenAmount;
        uint256 price;
        uint256 ltv;
        uint256 debtAmount;
        address debtToken;
    }

    //using to avoid stack too deep
    struct RepayParams {
        uint256 debtAmount;
        uint256 tokenAmount;
        uint256 repayAmount;
        address ceToken;
        address debtToken;
        uint256 dtScaled;
        uint256 ceScaled;
        address user;
    }


    //using to avoid stack too deep
    struct LiquidateParams {
        uint256 liqValue;
        uint256 burnLiquidatorCEAmount;
        uint256 burnBorrowerDebtAmount;
        uint256 liqBorrowerCEAmount;
    }

    event MintToTreasury(bytes32 id, uint256 tokenAmount, uint256 ceAmount);
    event Deposit(address user, bytes32 id, bytes32 chainId, uint256 tokenAmount, uint256 ceAmount);
    event Withdraw(address user, address to, bytes32 id, bytes32 chainId, uint256 tokenAmount, uint256 ceAmount);
    event Borrow(address user, address to, bytes32 id, bytes32 chainId, uint256 tokenAmount, uint256 debtAmount);
    event Repay(address user, bytes32 id, bytes32 chainId, uint256 tokenAmount, uint256 debtAmount, uint256 ceAmount);
    event Liquidate(address user, address liquidator, bytes32 debtId, bytes32 collateralId, 
        uint256 collateralAmount, uint256 burnDebtAmount, uint256 repayAmount, uint256 discount);
    event ChangePoolStatus(bytes32 id, bool enable);
    event ReceiveToken(address user, bytes32 id, uint256 tokenAmount);
    event Swap(bytes32 id, bytes32 srcChainId, bytes32 destChainId, uint256 tokenAmount);
}