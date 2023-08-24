// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IFeeProvider {
    /**
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/

    function setRoleManager(address roleManagerAddress) external;

    /**
     * @notice Sets core contract.
     * This function can only be accessed by the account with role SET_FEEPROVIDER_METHOD.
     * @param _coreAddress address of the core.
     **/
    function setCore(address _coreAddress) external;

    /**
     * @notice Configures Optimal Global Liquidity Factor.
     * This function can only be accessed by the account with role SET_FEEPROVIDER_METHOD.
     * @param _chainId - id of the chain.
     * @param _poolId - ids of the pool.
     * @param _liquidityFactor - optimal global liquidity factor for each pool in diff chain.
     **/
    function configureOptimalGlobalLiquidityFactor(
        bytes32 _chainId,
        bytes32[] memory _poolId,
        uint256[] memory _liquidityFactor
    ) external;

    /**
     * @notice Add the amount of fee to fee pool while withdrawing/borrowing an asset from a chain
     * @param _chainId - id of the chain.
     * @param _poolId - id of the pool.
     * @param _amount - amount of tokens deposited or withdrawn
     **/
    function setFeeAmount(
        bytes32 _chainId,
        bytes32 _poolId,
        uint256 _amount
    ) external returns (uint256);

    /**
     * @notice Deduct the amount of reward from fee pool while depositing/repaying an asset from a chain
     * @param chainId - id of the chain.
     * @param poolId - id of the pool.
     * @param amount - amount of tokens withdrawn or borrowed
     **/
    function setRewardAmount(
        bytes32 chainId,
        bytes32 poolId,
        uint256 amount
    ) external returns (uint256);

    /**
     * @notice Deduct the amount of reward from fee pool while swapping
     * This function can only be accessed by the account with role POOL.
     * @param chainId - id of the chain.
     * @param poolId - id of the pool.
     * @param amount - amount of tokens swapped and deposited to the chain
     **/
    function setRewardAmountForSwap(
        bytes32 chainId,
        bytes32 poolId,
        uint256 amount
    ) external returns (uint256);

    /**
     * @notice Returns the amount of fee while withdrawing/borrowing an asset from a chain
     * @param _chainId - id of the chain.
     * @param _poolId - id of the pool.
     * @param _amount - amount of tokens deposited or withdrawn
     **/
    function getFeeAmount(
        bytes32 _chainId,
        bytes32 _poolId,
        uint256 _amount
    ) external view returns (uint256);

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
    ) external view returns (uint256);

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
    ) external view returns (uint256);
}
