// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ICore.sol";
import "./interfaces/IRoleManager.sol";

string constant TAG = "FeeProvider";

/**
 * Title FeeProvider
 * Pool interact with FeeProvider for getting fee and reward amount.
 **/
contract FeeProvider is Initializable, OwnableUpgradeable {
    using SafeMath for uint256;

    mapping(bytes32 => mapping(bytes32 => uint256))
        public OPTIMAL_GLOBAL_LIQUIDITY_FACTOR;
    mapping(bytes32 => mapping(bytes32 => uint256)) public BASE_FEE;
    mapping(bytes32 => mapping(bytes32 => uint256)) public MAX_FEE;

    address public core;
    address public roleManager;

    /**
     * @dev Modifier that checks if caller has a specific role.
     **/
    modifier onlyRole(bytes32 role) {
        IRoleManager(roleManager).checkRole(role, _msgSender());
        _;
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    function setRoleManager(address roleManagerAddress) external onlyOwner {
        roleManager = roleManagerAddress;
    }

    function setCore(address coreAddress) external onlyRole(IRoleManager(roleManager).SET_FEEPROVIDER_METHOD()) {
        core = coreAddress;
    }

    /**
     * @dev Configures Optimal Global Liquidity Factor.
     * This function can only be accessed by the contract owner.
     * @param _chainId ids of the chain.
     * @param _poolId ids of the pool.
     * @param _liquidityFactor optimal global liquidity factor for each pool in diff chain.
     **/
    function configureOptimalGlobalLiquidityFactor(
        bytes32[] memory _chainId,
        bytes32[] memory _poolId,
        uint256[] memory _liquidityFactor
    ) external onlyRole(IRoleManager(roleManager).SET_FEEPROVIDER_METHOD()) {
        require(
            _chainId.length == _poolId.length &&
                _poolId.length == _liquidityFactor.length,
            string.concat(TAG,": Arguments number mismatched")
        );
        for (uint256 i = 0; i < _poolId.length; i++) {
            OPTIMAL_GLOBAL_LIQUIDITY_FACTOR[_chainId[i]][
                _poolId[i]
            ] = _liquidityFactor[i];
        }
    }


    function configureBaseFee(
        bytes32[] memory _chainId,
        bytes32[] memory _poolId,
        uint256[] memory _baseFee
    ) external onlyRole(IRoleManager(roleManager).SET_FEEPROVIDER_METHOD()) {
        require(
            _chainId.length == _poolId.length &&
                _poolId.length == _baseFee.length,
            string.concat(TAG, ": Arguments number mismatched")
        );
        for (uint256 i = 0; i < _poolId.length; i++) {
            BASE_FEE[_chainId[i]][_poolId[i]] = _baseFee[i];
        }
    }

    function configureMaxFee(
        bytes32[] memory _chainId,
        bytes32[] memory _poolId,
        uint256[] memory _maxFee
    ) external onlyRole(IRoleManager(roleManager).SET_FEEPROVIDER_METHOD()) {
        require(
            _chainId.length == _poolId.length &&
                _poolId.length == _maxFee.length,
            string.concat(TAG,": Arguments number mismatched")
        );
        for (uint256 i = 0; i < _poolId.length; i++) {
            MAX_FEE[_chainId[i]][_poolId[i]] = _maxFee[i];
        }
    }

    function getFeeAmount(
        bytes32 _chainId,
        bytes32 _poolId
    ) public view returns (uint256) {
        uint256 globalLiquidityFactor = _getGlobalLiquidityFactor(
            _chainId,
            _poolId
        );
        uint256 optimalGlobalLiquidityFactor = OPTIMAL_GLOBAL_LIQUIDITY_FACTOR[
            _chainId
        ][_poolId];
        uint256 initialFee;
        if (globalLiquidityFactor > 0) {
            initialFee = BASE_FEE[_chainId][_poolId].add(
                (optimalGlobalLiquidityFactor.sub(globalLiquidityFactor))
                    .mul(optimalGlobalLiquidityFactor)
                    .div(globalLiquidityFactor)
            );
        }
        if (initialFee < 0) {
            initialFee = 0;
        }
        uint256 maxFee = MAX_FEE[_chainId][_poolId];
        return maxFee <= initialFee ? maxFee : initialFee;
    }

    /**
     * @dev Computes the global liquidity factor of an asset for a chain
     * @param _chainId id of the chain.
     * @param _poolId id of the pool.
     **/
    function _getGlobalLiquidityFactor(
        bytes32 _chainId,
        bytes32 _poolId
    ) internal view returns (uint256) {
        uint256 totalLiquidity = ICore(core).totalLiquidity(_poolId);
        return
            totalLiquidity > 0
                ? ICore(core).getLiquidity(_chainId, _poolId).div(
                    totalLiquidity
                )
                : 0;
    }
}
