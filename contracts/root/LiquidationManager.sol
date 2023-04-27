// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/IDebtToken.sol";
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
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;

    uint256 public constant MAX_HEALTH_FACTOR = 1e18;

    address public roleManager;
    address public core;
    IOracle public oracle;

    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /**
     * @dev Modifier that checks if caller has a specific role.
     **/
    modifier onlyRole(bytes32 role) {
        IRoleManager(roleManager).checkRole(role, _msgSender());
        _;
    }

    function setRoleManager(address roleManagerAddress) external onlyOwner {
        roleManager = roleManagerAddress;
    }
    
    function setCore(address coreAddress) external onlyRole(IRoleManager(roleManager).SET_LIQUIDATION_METHOD()) {
        core = coreAddress;
    }

    function setOracle(IOracle oracleAddress) external onlyRole(IRoleManager(roleManager).SET_LIQUIDATION_METHOD()) {
        oracle = oracleAddress;
    }

    // calculate liquidate info and avoid stack too deep error
    function _buildLiquidateParams(
        bytes32 collateralId,
        bytes32 debtId,
        uint256 collateralAmount,
        uint256 discount
    ) internal view returns (Data.LiquidateParams memory params) {
        Data.ReserveData memory collateralReserve = ICore(core).reserves(
            collateralId
        );
        Data.ReserveData memory debtReserve = ICore(core).reserves(debtId);
        params.liqCEAmount = collateralAmount.mul(1e18).div(
            collateralReserve.ceScaled
        );
        params.liqValue = collateralAmount
            .mul(oracle.getSinglePrice(collateralId))
            .div(1e18);

        uint256 burnValue = params.liqValue.sub(
            params.liqValue.mul(discount).div(1e18)   
        ); // bonus
        uint256 burnTokenAmount = burnValue.mul(1e18).div(
            oracle.getSinglePrice(debtId)
        );
        params.burnDebtAmount = burnTokenAmount.mul(1e18).div(
            debtReserve.dtScaled
        );
        params.repayDebtAmount = burnTokenAmount.mul(1e18).div(
            debtReserve.ceScaled
        );
    }

    /**
     * @dev liquidates the position of address `user`.
     * @param user the address whose position is to be liquidated
     * @param collateralId the pool id of the collateral asset
     * @param debtId the pool id of the debt asset
     * @param collateralAmount the collateral user want to liquidate
     **/
    function liquidate(
        address user,
        bytes32 collateralId,
        bytes32 debtId,
        uint256 collateralAmount // naming
    ) external nonReentrant {
        ICore(core).refresh(collateralId);
        ICore(core).refresh(debtId);
        Data.HealthData memory healthData = ICore(core).healthFactor(user);
        Data.ConfigData memory config = ICore(core).configs(collateralId);
        require(healthData.factor >= MAX_HEALTH_FACTOR, string.concat(TAG,": Cannot liquidate now"));

        uint256 currentLTV = healthData.debtValue.mul(1e18).div(
            healthData.collateralValue
        );

        uint256 discount;
        uint256 liqPercent = 1e18;
        if (currentLTV < 1e18) {
            discount = 1e36 / currentLTV - 999000000000000000;
            if (discount > config.liqMaxDiscount) {
                discount = config.liqMaxDiscount;
            }

            uint256 p1 = config.liqClosingFac.mul(1e18 - currentLTV).div(
                1e18 - config.liqThreshold
            );
            if (currentLTV > config.liqThreshold) {
                liqPercent = p1.add(
                    currentLTV.sub(config.liqThreshold).mul(1e18).div(
                        1e18 - config.liqThreshold
                    )
                );
            } else {
                liqPercent = p1.add(
                    config.liqThreshold.sub(currentLTV).mul(1e18).div(
                        1e18 - config.liqThreshold
                    )
                );
            }

            if (liqPercent > 1e18) {
                liqPercent = 1e18;
            }
        }

        Data.ReserveData memory debtReserve = ICore(core).reserves(debtId);
        Data.ReserveData memory collateralReserve = ICore(core).reserves(
            collateralId
        );
        Data.LiquidateParams memory params = _buildLiquidateParams(
            collateralId,
            debtId,
            collateralAmount,
            discount
        );
        require(
            healthData.collateralValue.mul(liqPercent).div(1e18) >=
                params.liqValue,
            "Closing factor exceed"
        );

        IDebtToken(debtReserve.debtToken).burn(user, params.burnDebtAmount);
        //change to ICEToken
        IDebtToken(debtReserve.ceToken).burn(
            msg.sender,
            params.repayDebtAmount
        );
        
        ICore(core).updateCeAndDebtSupply(
            debtId,
            debtReserve.ceSupply,
            debtReserve.debtSupply
        );

        IDebtToken(collateralReserve.ceToken).burn(user, params.liqCEAmount);
        IDebtToken(collateralReserve.ceToken).mint(
            msg.sender,
            params.liqCEAmount
        );

        ICore(core).updateInterestRate(collateralId);
        ICore(core).updateInterestRate(debtId);
        emit Data.Liquidate(
            user,
            msg.sender,
            debtId,
            collateralId,
            collateralAmount,
            params.burnDebtAmount,
            params.repayDebtAmount,
            discount
        );
    }
}
