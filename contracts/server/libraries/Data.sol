// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

library Data {
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
        //is enable now
        bool enable;
    }

    struct RateData {
        uint bestRatio;
        uint slope1;
        uint slope2;
        uint baseRate;
    }
}
