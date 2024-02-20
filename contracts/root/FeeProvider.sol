// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ICore.sol";
import "./interfaces/IRoleManager.sol";

string constant TAG = "FeeProvider";

/**
 * @title FeeProvider
 * @notice Pool interact with FeeProvider for getting fee and reward amount.
 **/
contract FeeProvider is Initializable, ContextUpgradeable {
    using SafeMathUpgradeable for uint256;

    //---------------------------------------------------------------------------
    // CONSTANTS
    uint256 public constant DENOMINATOR = 1e18;
    uint256 public constant DELTA_1 = 6000 * 1e14;
    uint256 public constant DELTA_2 = 500 * 1e14;
    uint256 public constant LAMBDA_1 = 100 * 1e14;
    uint256 public constant LAMBDA_2 = 9900 * 1e14;

    // VARIABLES
    mapping(bytes32 => mapping(bytes32 => uint256))
        public OPTIMAL_GLOBAL_LIQUIDITY_FACTOR;

    mapping(bytes32 => mapping(bytes32 => uint256)) public feeAmount;

    address public core;
    address public roleManager;

    error ArgumentsMismatch(string contractTAG);
    error NotEnoughLiquidity(string contractTAG, uint256 liquidity);
    error OutOfBoundBalance(string contractTAG);
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

    /**
     * @notice Initilize the contract.
     * @param roleManagerAddress - Address of the roleManager contract.
     **/
    function initialize(address roleManagerAddress) public initializer {
        roleManager = roleManagerAddress;
    }

    /**
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/
    function setRoleManager(
        address roleManagerAddress
    ) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    /**
     * @notice Sets core contract.
     * This function can only be accessed by the account with role SET_FEEPROVIDER_METHOD.
     * @param coreAddress address of the core.
     **/
    function setCore(
        address coreAddress
    ) external onlyRole(IRoleManager(roleManager).SET_FEEPROVIDER_METHOD()) {
        core = coreAddress;
    }

    /**
     * @notice Configures Optimal Global Liquidity Factor.
     * This function can only be accessed by the account with role SET_FEEPROVIDER_METHOD.
     * @param chainId - id of the chain.
     * @param poolId - ids of the pool.
     * @param liquidityFactor - optimal global liquidity factor for each pool in diff chain.
     **/
    function configureOptimalGlobalLiquidityFactor(
        bytes32 chainId,
        bytes32[] memory poolId,
        uint256[] memory liquidityFactor
    ) external onlyRole(IRoleManager(roleManager).SET_FEEPROVIDER_METHOD()) {
        if (poolId.length != liquidityFactor.length)
            revert ArgumentsMismatch(TAG);

        for (uint256 i = 0; i < poolId.length; i++) {
            OPTIMAL_GLOBAL_LIQUIDITY_FACTOR[chainId][poolId[i]] = liquidityFactor[i];
        }
    }

    /**
     * @notice Add the amount of fee to fee pool while withdrawing/borrowing an asset from a chain
     * This function can only be accessed by the account with role POOL.
     * @param chainId - id of the chain.
     * @param poolId - id of the pool.
     * @param amount - amount of tokens withdrawn or borrowed
     **/
    function setFeeAmount(
        bytes32 chainId,
        bytes32 poolId,
        uint256 amount
    ) external onlyRole(IRoleManager(roleManager).POOL()) returns (uint256 fee)
    {
        fee = getFeeAmount(chainId, poolId, amount);
        feeAmount[chainId][poolId] += fee;
    }

    /**
     * @notice Deduct the amount of reward from fee pool while depositing/repaying an asset from a chain
     * This function can only be accessed by the account with role POOL.
     * @param chainId - id of the chain.
     * @param poolId - id of the pool.
     * @param amount - amount of tokens withdrawn or borrowed
     **/
    function setRewardAmount(
        bytes32 chainId,
        bytes32 poolId,
        uint256 amount
    ) external onlyRole(IRoleManager(roleManager).POOL()) returns (uint256 reward)
    {
        reward = getRewardAmount(chainId, poolId, amount);
        feeAmount[chainId][poolId] -= reward;
    }

    /**
     * @notice Deduct the amount of reward from fee pool while swapping
     * This function can only be accessed by the account with role POOL.
     * @param chainId - id of the chain.
     * @param poolId - id of the pool.
     * @param amount - amount of tokens amount of tokens swapped and deposited to the chain
     **/
    function setRewardAmountForSwap(
        bytes32 chainId,
        bytes32 poolId,
        uint256 amount
    ) external onlyRole(IRoleManager(roleManager).POOL()) returns (uint256 reward)
    {
        reward = getRewardAmountForSwap(chainId, poolId, amount);
        feeAmount[chainId][poolId] -= reward;
    }

    /**
     * @notice Returns the amount of fee while withdrawing/borrowing an asset from a chain
     * @param chainId - id of the chain.
     * @param poolId - id of the pool.
     * @param amount - amount of tokens withdrawn or borrowed
     **/
    function getFeeAmount(
        bytes32 chainId,
        bytes32 poolId,
        uint256 amount
    ) public view returns (uint256 fee) {
        uint256 beforeLiquidity = ICore(core).getLiquidity(chainId, poolId);
        uint256 totalLiquidity = ICore(core).totalLiquidity(poolId);

        if (beforeLiquidity < amount) {
            revert NotEnoughLiquidity(TAG, beforeLiquidity);
        }

        uint256 afterLiquidity = beforeLiquidity.sub(amount);
        uint256 optimalFactor = OPTIMAL_GLOBAL_LIQUIDITY_FACTOR[chainId][poolId];

        uint256 safeZoneMax = optimalFactor
            .mul(totalLiquidity.sub(amount))
            .div(DENOMINATOR)
            .mul(DELTA_1)
            .div(DENOMINATOR);

        uint256 safeZoneMin = optimalFactor
            .mul(totalLiquidity.sub(amount))
            .div(DENOMINATOR)
            .mul(DELTA_2)
            .div(DENOMINATOR);

        if (afterLiquidity >= safeZoneMax) {
            // no fee zone
            fee = 0;
        } else if (afterLiquidity >= safeZoneMin) {
            // safe zone
            uint256 proxyBeforeLiquidity = beforeLiquidity < safeZoneMax
                ? beforeLiquidity
                : safeZoneMax;

            fee = _getTrapezoidArea(
                LAMBDA_1,
                0,
                safeZoneMax,
                safeZoneMin,
                proxyBeforeLiquidity,
                afterLiquidity
            );

        } else {
            // danger zone
            if (beforeLiquidity >= safeZoneMin) {
                // across 2 or 3 zones
                // part 1
                uint256 proxyBeforeLiquidity = beforeLiquidity < safeZoneMax? beforeLiquidity: safeZoneMax;

                fee = _getTrapezoidArea(
                    LAMBDA_1,
                    0,
                    safeZoneMax,
                    safeZoneMin,
                    proxyBeforeLiquidity,
                    safeZoneMin
                );
                // part 2
                fee += _getTrapezoidArea(
                    LAMBDA_2,
                    LAMBDA_1,
                    safeZoneMin,
                    0,
                    safeZoneMin,
                    afterLiquidity
                );
                
            } else {
                // only in danger zone
                // part 2 only
                fee = _getTrapezoidArea(
                    LAMBDA_2,
                    LAMBDA_1,
                    safeZoneMin,
                    0,
                    beforeLiquidity,
                    afterLiquidity
                );
            }
        }
    }

    /**
     * @notice Returns the amount of reward while depositing/repaying an asset from a chain
     * @param chainId - id of the chain.
     * @param poolId - id of the pool.
     * @param amount - amount of tokens deposited or repayed
     **/
    function getRewardAmount(
        bytes32 chainId,
        bytes32 poolId,
        uint256 amount
    ) public view returns (uint256 reward) {
        uint256 beforeLiquidity = ICore(core).getLiquidity(chainId, poolId);
        uint256 totalLiquidity = ICore(core).totalLiquidity(poolId);
        uint256 optimalFactor = OPTIMAL_GLOBAL_LIQUIDITY_FACTOR[chainId][poolId];

        uint256 safeZoneMax = optimalFactor
            .mul(totalLiquidity)
            .div(DENOMINATOR)
            .mul(DELTA_1)
            .div(DENOMINATOR);

        if (beforeLiquidity > safeZoneMax) {
            return 0;
        }
        uint256 newSafeZoneMax = optimalFactor
            .mul(totalLiquidity.add(amount))
            .div(DENOMINATOR)
            .mul(DELTA_1)
            .div(DENOMINATOR);
       
        reward = (feeAmount[chainId][poolId].mul(amount)).div(
            newSafeZoneMax.sub(beforeLiquidity)
        );
        if (reward > feeAmount[chainId][poolId]) {
            reward = feeAmount[chainId][poolId];
        }
    }

    /**
     * @notice Returns the amount of reward while swapping
     * @param chainId - id of the chain.
     * @param poolId - id of the pool.
     * @param amount - amount of tokens amount of tokens swapped and deposited to the chain
     **/
    function getRewardAmountForSwap(
        bytes32 chainId,
        bytes32 poolId,
        uint256 amount
    ) public view returns (uint256 reward) {
        uint256 beforeLiquidity = ICore(core).getLiquidity(chainId, poolId);
        uint256 totalLiquidity = ICore(core).totalLiquidity(poolId);
        uint256 optimalFactor = OPTIMAL_GLOBAL_LIQUIDITY_FACTOR[chainId][poolId];

        uint256 safeZoneMax = optimalFactor
            .mul(totalLiquidity)
            .div(DENOMINATOR)
            .mul(DELTA_1)
            .div(DENOMINATOR);

        if (beforeLiquidity > safeZoneMax) {
            return 0;
        }
       
        reward = (feeAmount[chainId][poolId].mul(amount)).div(
            safeZoneMax.sub(beforeLiquidity)
        );
        if (reward > feeAmount[chainId][poolId]) {
            reward = feeAmount[chainId][poolId];
        }
    }

    /**
     * @notice Computes the global liquidity factor of an asset for a chain
     * @param chainId id of the chain.
     * @param poolId id of the pool.
     **/
    function getGlobalLiquidityFactor(
        bytes32 chainId,
        bytes32 poolId
    ) external view returns (uint256) {
        uint256 totalLiquidity = ICore(core).totalLiquidity(poolId);
        if (totalLiquidity == 0){
            return 0;
        }
        return ICore(core).getLiquidity(chainId, poolId).mul(DENOMINATOR).div(totalLiquidity);
    }

    /**
     * @notice Returns the withdrawable amount of an asset for a chain without incurring fee
     * @param chainId id of the chain.
     * @param poolId id of the pool.
     **/
    function getWithdrawAbleAmountWithoutFee(
        bytes32 chainId,
        bytes32 poolId
    ) external view returns (uint256) {
        uint256 totalLiquidity = ICore(core).totalLiquidity(poolId);
        uint256 beforeLiquidity = ICore(core).getLiquidity(chainId, poolId);
        uint256 optimalFactor = OPTIMAL_GLOBAL_LIQUIDITY_FACTOR[chainId][poolId];

        uint256 excessLiquidity = beforeLiquidity.sub((optimalFactor).mul(totalLiquidity).div(DENOMINATOR).mul(DELTA_1).div(DENOMINATOR));
        uint256 excessFactor = DENOMINATOR.sub((optimalFactor).mul(DELTA_1).div(DENOMINATOR));
        return excessLiquidity.mul(DENOMINATOR).div(excessFactor);
    }

    function _getTrapezoidArea(
        uint256 lambda,
        uint256 yOffset,
        uint256 xUpperBound,
        uint256 xLowerBound,
        uint256 xStart,
        uint256 xEnd
    ) internal pure returns (uint256) {
        if (xEnd < xLowerBound || xStart > xUpperBound) {
            revert OutOfBoundBalance(TAG);
        }
       
        uint256 xBoundWidth = xUpperBound.sub(xLowerBound);

        // xStartDrift = xUpperBound.sub(xStart);
        uint256 yStart = xUpperBound
            .sub(xStart)
            .mul(lambda)
            .div(xBoundWidth)
            .add(yOffset);

        // xEndDrift = xUpperBound.sub(xEnd)
        uint256 yEnd = xUpperBound.sub(xEnd).mul(lambda).div(xBoundWidth).add(
            yOffset
        );

        // compute the area
        uint256 deltaX = xStart.sub(xEnd);
        return yStart.add(yEnd).mul(deltaX).div(2).div(1e18);
    }
}
