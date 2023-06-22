// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ICore.sol";
import "./interfaces/IRoleManager.sol";

string constant TAG = "FeeProvider";

/**
 * Title FeeProvider
 * Pool interact with FeeProvider for getting fee and reward amount.
 **/
contract FeeProvider is Initializable, ContextUpgradeable {
    using SafeMathUpgradeable for uint256;

    mapping(bytes32 => mapping(bytes32 => uint256))
        public OPTIMAL_GLOBAL_LIQUIDITY_FACTOR;
    mapping(bytes32 => mapping(bytes32 => uint256)) public BASE_FEE;
    mapping(bytes32 => mapping(bytes32 => uint256)) public MAX_FEE;

    address public core;
    address public roleManager;

    error ArgumentsMismatch();
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
        roleManager = roleManagerAddress;
    }

    // Set contract addresses
    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    function setCore(
        address coreAddress
    ) external onlyRole(IRoleManager(roleManager).SET_FEEPROVIDER_METHOD()) {
        core = coreAddress;
    }

    // Set different factors
    function configureOptimalGlobalLiquidityFactor(
        bytes32[] memory chainId,
        bytes32[] memory poolId,
        uint256[] memory liquidityFactor
    ) external onlyRole(IRoleManager(roleManager).SET_FEEPROVIDER_METHOD()) {
        // require(
        //     chainId.length == poolId.length &&
        //         poolId.length == liquidityFactor.length,
        //     string.concat(TAG, ": Arguments number mismatched")
        // );

        if(chainId.length != poolId.length)
            revert ArgumentsMismatch();

        if(poolId.length != liquidityFactor.length)
            revert ArgumentsMismatch();

        for (uint256 i = 0; i < poolId.length; i++) {
            OPTIMAL_GLOBAL_LIQUIDITY_FACTOR[chainId[i]][
                poolId[i]
            ] = liquidityFactor[i];
        }
    }

    function configureBaseFee(
        bytes32[] memory chainId,
        bytes32[] memory poolId,
        uint256[] memory baseFee
    ) external onlyRole(IRoleManager(roleManager).SET_FEEPROVIDER_METHOD()) {
        // require(
        //     chainId.length == poolId.length && poolId.length == baseFee.length,
        //     string.concat(TAG, ": Arguments number mismatched")
        // );

        if(chainId.length != poolId.length)
            revert ArgumentsMismatch();

        if(poolId.length != baseFee.length)
            revert ArgumentsMismatch();

        for (uint256 i = 0; i < poolId.length; i++) {
            BASE_FEE[chainId[i]][poolId[i]] = baseFee[i];
        }
    }

    function configureMaxFee(
        bytes32[] memory chainId,
        bytes32[] memory poolId,
        uint256[] memory maxFee
    ) external onlyRole(IRoleManager(roleManager).SET_FEEPROVIDER_METHOD()) {
        // require(
        //     chainId.length == poolId.length && poolId.length == maxFee.length,
        //     string.concat(TAG, ": Arguments number mismatched")
        // );

        if(chainId.length != poolId.length)
            revert ArgumentsMismatch();

        if(poolId.length != maxFee.length)
            revert ArgumentsMismatch();

        for (uint256 i = 0; i < poolId.length; i++) {
            MAX_FEE[chainId[i]][poolId[i]] = maxFee[i];
        }
    }

    function getFeeAmount(
        bytes32 chainId,
        bytes32 poolId
    ) public view returns (uint256) {
        uint256 globalLiquidityFactor = _getGlobalLiquidityFactor(
            chainId,
            poolId
        );

        uint256 optimalGlobalLiquidityFactor = OPTIMAL_GLOBAL_LIQUIDITY_FACTOR[
            chainId
        ][poolId];

        uint256 initialFee;
        if (globalLiquidityFactor > 0) {
            initialFee = BASE_FEE[chainId][poolId].add(
                (optimalGlobalLiquidityFactor.sub(globalLiquidityFactor))
                    .mul(optimalGlobalLiquidityFactor)
                    .div(globalLiquidityFactor)
            );
        }

        if (initialFee < 0) {
            initialFee = 0;
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
            totalLiquidity > 0
                ? ICore(core).getLiquidity(chainId, poolId).div(totalLiquidity)
                : 0;
    }
}
