// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IFeeProvider {
    /**
     * @notice Configures role manager address
     * This function can only be accessed by the owner.
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
    * @notice Configures upper limit of the fee for withdraw. 
    * This function can only be accessed by the account with role SET_FEEPROVIDER_METHOD.
    * @param _chainId - ids of the chain.
    * @param _poolId - ids of the pool.
    * @param _maxFee - upper limit of fee for each pool in diff chain.
    
    **/
    function configureMaxFee(
        bytes32[] memory _chainId,
        bytes32[] memory _poolId,
        uint256[] memory _maxFee
    ) external;

    /**
     * @notice Configures Base Global Liquidity Factor.
     * This function can only be accessed by the account with role SET_FEEPROVIDER_METHOD.
     * @param _chainId - ids of the chain.
     * @param _poolId - ids of the pool.
     * @param _baseFee - base fee for each pool in diff chain.
     **/
    function configureBaseFee(
        bytes32[] memory _chainId,
        bytes32[] memory _poolId,
        uint256[] memory _baseFee
    ) external;

    /**
     * @notice Configures Optimal Global Liquidity Factor.
     * This function can only be accessed by the account with role SET_FEEPROVIDER_METHOD.
     * @param _chainId - ids of the chain.
     * @param _poolId - ids of the pool.
     * @param _liquidityFactor - optimal global liquidity factor for each pool in diff chain.
     **/
    function configureOptimalGlobalLiquidityFactor(
        bytes32[] memory _chainId,
        bytes32[] memory _poolId,
        uint256[] memory _liquidityFactor
    ) external;

    /**
     * @notice Returns the amount of fee while withdrawing/borrowing an asset from a chain
     * @param _chainId - id of the chain.
     * @param _poolId - id of the pool.
     **/
    function getFeeAmount(
        bytes32 _chainId,
        bytes32 _poolId
    ) external view returns (uint256);
}
