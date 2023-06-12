// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

import "./interfaces/IDebtToken.sol";
import "./interfaces/ICEToken.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ICore.sol";
import "./interfaces/IRoleManager.sol";
import "./libraries/Data.sol";

string constant TAG = "LiquidationManager";

/** 
* Title LiquidationManager

* Users interact with LiquidationManager for Liquidate actions.
**/

contract LiquidationManager is
    Initializable,
    ReentrancyGuardUpgradeable,
    ContextUpgradeable
{
    using SafeMathUpgradeable for uint256;

    uint256 public constant MAX_HEALTH_FACTOR = 1e18;

    address public roleManager;
    address public core;
    IOracle public oracle;

    error CannotLiquidate(uint256 currentHealthFactor);
    error ClosingFactotExceeded();
    /**
     * @dev Modifier that checks if caller has a specific role.
     **/
    modifier onlyRole(bytes32 role) {
        IRoleManager(roleManager).checkRole(role, _msgSender());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address roleManagerAddress) public initializer {
        __ReentrancyGuard_init();
        roleManager = roleManagerAddress;
    }

    // Set contract addresses
    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    function setCore(
        address coreAddress
    ) external onlyRole(IRoleManager(roleManager).SET_LIQUIDATION_METHOD()) {
        core = coreAddress;
    }

    function setOracle(
        IOracle oracleAddress
    ) external onlyRole(IRoleManager(roleManager).SET_LIQUIDATION_METHOD()) {
        oracle = oracleAddress;
    }

    /**
     * e.g. borrower deposit A and borrow B
     * 1. calculate liqudate CEToken(A) amount from the underlying amount liquidator want to liquidate
     * 2. calculate DebtToken(B) amount from CEToken(A) borrower burn
     * 3. calculate CEToken(B) amount liquidator need to repay from DebtToken(B)
     **/
    function _buildLiquidateParams(
        bytes32 collateralId,
        bytes32 debtId,
        uint256 borrowerCollateral, // Amount of collateral of borrower that liquidator wants to liquidate
        uint256 discount
    ) internal view returns (Data.LiquidateParams memory params) {
        Data.PoolData memory collateralPool = ICore(core).pools(collateralId);
        Data.PoolData memory debtPool = ICore(core).pools(debtId);
        // CE token amount of borrower
        params.liqBorrowerCEAmount = borrowerCollateral.mul(1e18).div(
            collateralPool.ceScaled
        );
        // Price of collateral liquidator want to liquidate
        params.liqValue = borrowerCollateral
            .mul(oracle.getSinglePrice(collateralId))
            .div(1e18);
        // Price after discount
        uint256 liqValueAfterDiscount = params.liqValue.sub(
            params.liqValue.mul(discount).div(1e18)
        );
        // Amount after discount
        uint256 liqAmountAfterDiscount = liqValueAfterDiscount.mul(1e18).div(
            oracle.getSinglePrice(debtId)
        );
        // Repay debt amount of borrower
        params.burnBorrowerDebtAmount = liqAmountAfterDiscount.mul(1e18).div(
            debtPool.dtScaled
        );
        // Deduct equivalent collateral of liquidator
        params.burnLiquidatorCEAmount = liqAmountAfterDiscount.mul(1e18).div(
            debtPool.ceScaled
        );
    }

    function liquidate(
        address user,
        bytes32 collateralId,
        bytes32 debtId,
        uint256 borrowerCollateral
    ) external nonReentrant {
        // refresh the pool data
        ICore(core).refresh(collateralId);
        ICore(core).refresh(debtId);

        // calculate borrower's data including total collateral and total debt
        Data.HealthData memory healthData = ICore(core).healthFactor(user);
        Data.ConfigData memory config = ICore(core).configs(collateralId);

        // whether borrower can be liquidated
        // require(
        //     healthData.factor >= MAX_HEALTH_FACTOR,
        //     string.concat(TAG, ": Cannot liquidate now")
        // );

        if(healthData.factor < MAX_HEALTH_FACTOR)
            revert CannotLiquidate(healthData.factor);

        // calculate LTV, and using formula to calculate liquidate discount and closing factor
        uint256 currentLTV = healthData.debtValue.mul(1e18).div(
            healthData.collateralValue
        );

        uint256 discount;
        uint256 liqPercent = 0;
        if (currentLTV < 1e18) {
            discount = 1e36 / currentLTV - 999000000000000000;
            if (discount > config.liqMaxDiscount) {
                discount = config.liqMaxDiscount;
            }

            uint256 numerator_a = config
                .liqClosingFac
                .mul(1e18).add(currentLTV);
            uint256 numerator_b = config
                .liqClosingFac
                .mul(currentLTV).add(config.liqThreshold);
            if(numerator_a > numerator_b) {
                liqPercent = numerator_a.sub(numerator_b).div(1e18 - config.liqThreshold);
            }

            if (liqPercent > 1e18) {
                liqPercent = 1e18;
            }
        }

        Data.PoolData memory debtPool = ICore(core).pools(debtId);
        Data.PoolData memory collateralPool = ICore(core).pools(collateralId);

        Data.LiquidateParams memory params = _buildLiquidateParams(
            collateralId,
            debtId,
            borrowerCollateral,
            discount
        );
        // require(
        //     healthData.collateralValue.mul(liqPercent).div(1e18) >=
        //         params.liqValue,
        //     "Closing factor exceed"
        // );

        if(healthData.collateralValue.mul(liqPercent).div(1e18) < params.liqValue)
            revert ClosingFactotExceeded();  //TODO: what to add here?
        // mint and burn CEToken and DebtToken then update supply
        IDebtToken(debtPool.debtToken).burn(
            user,
            params.burnBorrowerDebtAmount
        );
        ICEToken(debtPool.ceToken).burn(
            msg.sender,
            params.burnLiquidatorCEAmount
        );

        ICore(core).updateCeAndDebtSupply(
            debtId,
            debtPool.ceSupply.sub(params.burnLiquidatorCEAmount),
            debtPool.debtSupply.sub(params.burnBorrowerDebtAmount)
        );

        ICEToken(collateralPool.ceToken).burn(user, params.liqBorrowerCEAmount);
        ICEToken(collateralPool.ceToken).mint(
            msg.sender,
            params.liqBorrowerCEAmount
        );

        ICore(core).updateInterestRate(collateralId);
        ICore(core).updateInterestRate(debtId);
        emit Data.Liquidate(
            user,
            msg.sender,
            debtId,
            collateralId,
            borrowerCollateral,
            params.burnBorrowerDebtAmount,
            params.burnLiquidatorCEAmount,
            discount
        );
    }
}
