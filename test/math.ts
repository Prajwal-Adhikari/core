const { expect } = require("chai")
const { ethers, upgrades } = require("hardhat")

let BN = require("bignumber.js");
const { keccak256 } = require("ethers/lib/utils");

// interface LiquidateParams {
//     liqValue;
//     burnLiquidatorCEAmount;
//     burnBorrowerDebtAmount;
//     liqBorrowerCEAmount;
// }

async function buildLiquidateParam(
    currentLTV,
    collateralId,
    debtId,
    borrowerCollateral,
    core,
    oracle
){
    let collateralPool = await core.pools(collateralId);
    let debtPool = await core.pools(debtId);
    let config = await core.configs(collateralId);
    let discount;
    if (currentLTV < 1e18) {
        discount = (1e36 / currentLTV)- 999000000000000000;
        if (discount > config.liqMaxDiscount) {
            discount = config.liqMaxDiscount;
        }
    }
    console.log(discount);

    // CE token amount of borrower
    let liqBorrowerCEAmount = (borrowerCollateral*1e18)/collateralPool.ceScaled;
    // Price of collateral liquidator want to liquidate
    let liqValue = (borrowerCollateral * await oracle.getSinglePrice(collateralId))/1e18;
    // Price after discount
    let liqValueAfterDiscount = liqValue - (liqValue*discount)/(1e18);   
    // Amount after discount
    let liqValueAfterDiscountAmount = (liqValueAfterDiscount * 1e18)/(await oracle.getSinglePrice(debtId));
    // Repay debt amount of borrower
    let burnBorrowerDebtAmount = (liqValueAfterDiscountAmount * 1e18)/debtPool.dtScaled
    // Deduct equivalent collateral of liquidator
    let burnLiquidatorCEAmount = (liqValueAfterDiscountAmount * 1e18)/debtPool.ceScaled;
    
    return {
        liqValue: liqValue,
        burnLiquidatorCEAmount: burnLiquidatorCEAmount,
        burnBorrowerDebtAmount: burnBorrowerDebtAmount,
        liqBorrowerCEAmount: liqBorrowerCEAmount
    };
}

module.exports = {buildLiquidateParam}