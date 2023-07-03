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

    mapping(bytes32 => mapping(bytes32 => uint256))
        public OPTIMAL_GLOBAL_LIQUIDITY_FACTOR;
    mapping(bytes32 => mapping(bytes32 => uint256)) public BASE_FEE;
    mapping(bytes32 => mapping(bytes32 => uint256)) public MAX_FEE;

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
     * @notice Configures Base Global Liquidity Factor.
     * This function can only be accessed by the account with role SET_FEEPROVIDER_METHOD.
     * @param chainId - ids of the chain.
     * @param poolId - ids of the pool.
     * @param baseFee - base fee for each pool in diff chain.
     **/
    function configureBaseFee(
        bytes32[] memory chainId,
        bytes32[] memory poolId,
        uint256[] memory baseFee
    ) external onlyRole(IRoleManager(roleManager).SET_FEEPROVIDER_METHOD()) {
        if(chainId.length != poolId.length)
            revert ArgumentsMismatch(10);

        if(poolId.length != baseFee.length)
            revert ArgumentsMismatch(10);

        for (uint256 i = 0; i < poolId.length; i++) {
            BASE_FEE[chainId[i]][poolId[i]] = baseFee[i];
        }
    }

    /**
    * @notice Configures upper limit of the fee for withdraw. 
    * This function can only be accessed by the account with role SET_FEEPROVIDER_METHOD.
    * @param chainId - ids of the chain.
    * @param poolId - ids of the pool.
    * @param maxFee - upper limit of fee for each pool in diff chain.
    **/
    function configureMaxFee(
        bytes32[] memory chainId,
        bytes32[] memory poolId,
        uint256[] memory maxFee
    ) external onlyRole(IRoleManager(roleManager).SET_FEEPROVIDER_METHOD()) {
        if(chainId.length != poolId.length)
            revert ArgumentsMismatch(10);

        if(poolId.length != maxFee.length)
            revert ArgumentsMismatch(10);

        for (uint256 i = 0; i < poolId.length; i++) {
            MAX_FEE[chainId[i]][poolId[i]] = maxFee[i];
        }
    }

    /**
     * @notice Returns the amount of fee while withdrawing/borrowing an asset from a chain
     * @param chainId - id of the chain.
     * @param poolId - id of the pool.
     **/
    function getFeeAmount(
        bytes32 chainId,
        bytes32 poolId
    ) public view returns (uint256) {
        uint256 globalLiquidityFactor = _getGlobalLiquidityFactor(
            chainId,
            poolId
        );

        uint256 optimalGlobalLiquidityFactor = OPTIMAL_GLOBAL_LIQUIDITY_FACTOR[chainId][poolId];

        uint256 initialFee;
        if (globalLiquidityFactor > 0) {
            if (globalLiquidityFactor < optimalGlobalLiquidityFactor) {
                initialFee = BASE_FEE[chainId][poolId].add(
                    (optimalGlobalLiquidityFactor.sub(globalLiquidityFactor))
                        .mul(optimalGlobalLiquidityFactor)
                        .div(globalLiquidityFactor)
                );
            } else {
                initialFee = BASE_FEE[chainId][poolId];
            }
        } else {
            initialFee = MAX_FEE[chainId][poolId];
        }

        uint256 maxFee = MAX_FEE[chainId][poolId];
        return maxFee <= initialFee ? maxFee : initialFee;
    }

    /**
     * @dev Computes the global liquidity factor of an asset for a chain
     * @param chainId id of the chain.
     * @param poolId id of the pool.
     **/
    function _getGlobalLiquidityFactor(
        bytes32 chainId,
        bytes32 poolId
    ) internal view returns (uint256) {
        uint256 totalLiquidity = ICore(core).totalLiquidity(poolId);
        return
            totalLiquidity > 0 ? ICore(core).getLiquidity(chainId, poolId).mul(1e18).div(totalLiquidity) : 0;
    }
}
