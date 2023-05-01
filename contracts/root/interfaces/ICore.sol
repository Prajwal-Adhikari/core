// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "../libraries/Data.sol";

interface ICore {
    /**
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/
    function setRoleManager(address roleManagerAddress) external;

    /**
     * @notice Registers a new pool in the protocol.
     * This function can only be accessed by account with role INIT_POOL.
     * @param id - id of the pool to be created
     * @param config - a ConfigData struct containing the interest rate and liqudation variables.
     * @param _ceToken - address to the ceToken smart contract for this pool.
     * @param _debtToken - address to the debtToken smart contract for this pool.
     **/
    function initPool(
        bytes32 id,
        Data.ConfigData memory config,
        address _ceToken,
        address _debtToken
    ) external;

    /**
     * @notice Updates the global protocol states after receiving deposit information
     * of amount `tokenAmount` from address `user` for pool with pool id 'id' from
     * chain with chain id `chainId`.
     * This function can only be accessed by account with role POOL.
     * @param id - pool id of pool where amount was deposited to
     * @param chainId -  chain id of chain deposited to
     * @param user - deposit address
     * @param tokenAmount - amount deposited
     **/

    function deposit(
        bytes32 id,
        bytes32 chainId,
        address user,
        uint256 tokenAmount
    ) external returns (uint256);

    /**
     * @notice Sends a withdraw request of amount `ceAmount` to address `user` from pool with pool id `id`
     * in chain with chain id `chainId`.
     * This function can only be accessed by account with role POOL.
     * @param id - pool id of pool to withdraw from
     * @param chainId - chain id of chain to withdraw from
     * @param ceAmount - amount to withdraw
     * @param user - withdraw address
     **/
    function withdraw(
        bytes32 id,
        bytes32 chainId,
        uint256 ceAmount,
        address user
    ) external returns (uint256);

    /**
     * @notice Sends a borrow request of amount `tokenAmount` to address `user` from pool with pool id `id`
     * in chain with chain id `chainId`.
     * This function can only be accessed by account with role POOL.
     * @param id - pool id of pool to borrow from
     * @param chainId - chain id of chain to borrow from
     * @param tokenAmount - amount to borrow
     * @param user - borrow address
     **/
    function borrow(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount,
        address user
    ) external returns (uint256);

    /**
     * @notice Updates the global protocol states after receiving repay information
     * of amount `tokenAmount` from address `user` for pool with pool id 'id' from
     * chain with chain id `chainId`.
     * @param id - pool id of pool where amount was repaid to
     * @param chainId - chain id of chain repaid from
     * @param user - repay address
     * @param tokenAmount - amount repaid
     **/
    function repay(
        bytes32 id,
        bytes32 chainId,
        address user,
        uint256 tokenAmount
    ) external returns (uint256, uint256, uint256);

    /**
     * @notice Freezes/Unfreezes a pool with pool id `id`.
     * This function can only be accessed by account with role POOL_STATUS.
     * @param id - id of the pool to freeze/unfreeze
     * @param enable - bool to freeze/unfreeze
     **/
    function changePoolStatus(bytes32 id, bool enable) external;

    /**
     * @notice Updates ceSupply and debtSupply of the pool
     * This function can only be accessed by account with role LIQUIDATION_MANAGER.
     * @param id - id of the pool
     * @param ceAmount - amount of ceSupply
     * @param debtAmount - amount of debtSupply
     **/
    function updateCeAndDebtSupply(
        bytes32 id,
        uint256 ceAmount,
        uint256 debtAmount
    ) external;

    /**
     * @notice Swaps liquidity amount from one chain to another
     * This function can only be accessed by account with role POOL.
     * @param id - pool id of the asset.
     * @param srcChainId - chain id of the source chain
     * @param destChainId - chain id of the destination chain
     * @param tokenAmount - liquidity amount
     **/

    function swap(
        bytes32 id,
        bytes32 srcChainId,
        bytes32 destChainId,
        uint256 tokenAmount
    ) external;

    /**
     * @notice Refreshes the parameters of the pool.
     * This function is public.
     * @param id - pool id
     **/
    function refresh(bytes32 id) external;

    /**
     * @notice Updates the interest rate and utilization ratio of the pool.
     * This function is public.
     * @param id - pool id
     **/
    function updateInterestRate(bytes32 id) external;

    /**
     * @notice Returns the health factor of the address `user`.
     * @param user - wallet address for which the health factor is calculated.
     **/
    function healthFactor(
        address user
    ) external view returns (Data.HealthData memory health);

    /**
     * @notice Reverts if the health factor is not less than MAX_HEALTH_FACTOR
     * @param user - wallet address for which the health factor is calculated.
     **/
    function checkHealth(address user) external view;

    /**
     * @notice Returns liquidity of an asset for a chain
     * @param _chainId - id of the chain.
     * @param _poolId - id of the pool.
     **/
    function getLiquidity(
        bytes32 _chainId,
        bytes32 _poolId
    ) external view returns (uint256);

    /**
     * @notice Returns total liquidity of an asset across chains
     * @param _poolId - id of the pool.
     **/
    function totalLiquidity(bytes32 _poolId) external view returns (uint256);

    /**
     * @notice Returns pool parametes for an asset
     * @param _poolId - id of the pool.
     **/
    function pools(
        bytes32 _poolId
    ) external view returns (Data.PoolData memory pool);

    /**
     * @notice Returns config parametes for an asset
     * @param _poolId - id of the pool.
     **/
    function configs(
        bytes32 _poolId
    ) external view returns (Data.ConfigData memory config);


    function getDTScaled(bytes32 _poolId) external view returns (uint256);

    function getCEScaled(bytes32 _poolId) external view returns (uint256);
}
