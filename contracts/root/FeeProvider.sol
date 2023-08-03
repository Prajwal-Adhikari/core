// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ICore.sol";
import "./interfaces/IRoleManager.sol";

/**
 * @title FeeProvider
 * @notice Pool interact with FeeProvider for getting fee and reward amount.
 **/
contract FeeProvider is Initializable, ContextUpgradeable {
    using SafeMathUpgradeable for uint256;

    //---------------------------------------------------------------------------
    // CONSTANTS
    uint256 public constant DELTA_1 = 6000 * 1e14;
    uint256 public constant DELTA_2 = 500 * 1e14;
    uint256 public constant LAMBDA_1 = 4000 * 1e14;
    uint256 public constant LAMBDA_2 = 996000 * 1e14;
    
    // VARIABLES
    mapping(bytes32 => mapping(bytes32 => uint256))
        public OPTIMAL_GLOBAL_LIQUIDITY_FACTOR;

    address public core;
    address public roleManager;

    error ArgumentsMismatch(uint contractCode);
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
     * @param roleManagerAddress - The EOA of role manager.
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
     * @param chainId - ids of the chain.
     * @param poolId - ids of the pool.
     * @param liquidityFactor - optimal global liquidity factor for each pool in diff chain.
     **/
    function configureOptimalGlobalLiquidityFactor(
        bytes32[] memory chainId,
        bytes32[] memory poolId,
        uint256[] memory liquidityFactor
    ) external onlyRole(IRoleManager(roleManager).SET_FEEPROVIDER_METHOD()) {
        if(chainId.length != poolId.length)
            revert ArgumentsMismatch(10);

        if(poolId.length != liquidityFactor.length)
            revert ArgumentsMismatch(10);

        for (uint256 i = 0; i < poolId.length; i++) {
            OPTIMAL_GLOBAL_LIQUIDITY_FACTOR[chainId[i]][
                poolId[i]
            ] = liquidityFactor[i];
        }
    }


    /**
     * @notice Returns the amount of fee while withdrawing/borrowing an asset from a chain
     * @param chainId - id of the chain.
     * @param poolId - id of the pool.
     * @param amount - amount of tokens deposited or withdrawn
     **/
    function getFeeAmount(
        bytes32 chainId,
        bytes32 poolId,
        uint256 amount
    ) external view returns (uint256 fee) {

        uint256 safeZoneMax = OPTIMAL_GLOBAL_LIQUIDITY_FACTOR[chainId][poolId].mul(DELTA_1).div(1e18);
        uint256 safeZoneMin = OPTIMAL_GLOBAL_LIQUIDITY_FACTOR[chainId][poolId].mul(DELTA_2).div(1e18);

        uint256 proxyGlobalLiquidityFactor;
        uint256 excessLiquidity;
        uint256 usedLiquidity;
        uint256 totalLiquidity = ICore(core).totalLiquidity(poolId);
        uint256 globalLiquidity = ICore(core).getLiquidity(chainId, poolId);
        uint256 globalLiquidityFactor = globalLiquidity.mul(1e18).div(totalLiquidity);
        uint256 globalLiquidityFactorAfter = (globalLiquidity.sub(amount)).mul(1e18).div(totalLiquidity.sub(amount));

    
        if (globalLiquidityFactorAfter >= safeZoneMax) {
            // no fee zone
            fee = 0;
        } else if (globalLiquidityFactorAfter >= safeZoneMin) {
            // safe zone
            if (globalLiquidityFactor < safeZoneMax ){
                proxyGlobalLiquidityFactor = globalLiquidityFactor;
            } else {
                proxyGlobalLiquidityFactor = safeZoneMax;
                uint256 safeZoneLiquidity = safeZoneMax.mul(totalLiquidity);
                excessLiquidity = ((globalLiquidity.sub(safeZoneLiquidity.div(1e18))).mul(1e18)).div((1e18) - (safeZoneMax));
            }

            fee = (_getTrapezoidArea(LAMBDA_1, 0, safeZoneMax, safeZoneMin, proxyGlobalLiquidityFactor, globalLiquidityFactorAfter).mul(amount.sub(excessLiquidity))).div(1e18);
        } else {
            // danger zone
            if (globalLiquidityFactor >= safeZoneMin) {
                // across 2 or 3 zones
                if (globalLiquidityFactor < safeZoneMax){
                    proxyGlobalLiquidityFactor = globalLiquidityFactor;
                    uint256 safeZoneLiquidity = safeZoneMin.mul(totalLiquidity);
                    usedLiquidity = ((globalLiquidity.sub(safeZoneLiquidity).div(1e18)).mul(1e18)).div((1e18) - (safeZoneMin));
                } else {
                    proxyGlobalLiquidityFactor = safeZoneMax;
                    uint256 safeZoneLiquidity = safeZoneMax.mul(totalLiquidity);
                    excessLiquidity = ((globalLiquidity.sub(safeZoneLiquidity.div(1e18))).mul(1e18)).div((1e18) - (safeZoneMax));
                    usedLiquidity = (totalLiquidity.sub(excessLiquidity)).mul(safeZoneMax.sub(safeZoneMin)).div((1e18) - (safeZoneMin));
                }
                // part 1
                uint256 feeBetweenMaxToMin = _getTrapezoidArea(LAMBDA_1, 0, safeZoneMax, safeZoneMin, proxyGlobalLiquidityFactor, safeZoneMin);

                fee = feeBetweenMaxToMin.mul(usedLiquidity).div(1e18);

                // part 2
                uint256 feeBelowMin = _getTrapezoidArea(LAMBDA_2, LAMBDA_1, safeZoneMin, 0, safeZoneMin, globalLiquidityFactorAfter);
                uint256 remainingLiquidity = (amount.sub(usedLiquidity));
                
                fee += feeBelowMin.mul(remainingLiquidity.sub(excessLiquidity)).div(1e18);

            } else {
                // only in danger zone
                // part 2 only
                fee = _getTrapezoidArea(LAMBDA_2, LAMBDA_1, safeZoneMin, 0, globalLiquidityFactor, globalLiquidityFactorAfter).mul(amount).div(1e18);
            }
        }
    }

    /**
     * @dev Computes the global liquidity factor of an asset for a chain
     * @param chainId id of the chain.
     * @param poolId id of the pool.
     **/
    function getGlobalLiquidityFactor(
        bytes32 chainId,
        bytes32 poolId
    ) external view returns (uint256) {
        uint256 totalLiquidity = ICore(core).totalLiquidity(poolId);
        return totalLiquidity > 0 ? ICore(core).getLiquidity(chainId, poolId).mul(1e18).div(totalLiquidity) : 0;
    }

    function _getTrapezoidArea(
        uint256 lambda,
        uint256 yOffset,
        uint256 xUpperBound,
        uint256 xLowerBound,
        uint256 xStart,
        uint256 xEnd
    ) internal pure returns (uint256) {
        require(xEnd >= xLowerBound && xStart <= xUpperBound, "Stargate: balance out of bound");
        uint256 xBoundWidth = xUpperBound.sub(xLowerBound);

        // xStartDrift = xUpperBound.sub(xStart);
        uint256 yStart = xUpperBound.sub(xStart).mul(lambda).div(xBoundWidth).add(yOffset);

        // xEndDrift = xUpperBound.sub(xEnd)
        uint256 yEnd = xUpperBound.sub(xEnd).mul(lambda).div(xBoundWidth).add(yOffset);

        // compute the area
        uint256 deltaX = xStart.sub(xEnd);
        return yStart.add(yEnd).mul(deltaX).div(2).div(1e18);
    }

}


   

    

