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
    ) external returns (uint256, uint256);

    /**
     * @notice Sends a withdraw request of amount `tokenAmount` to address `user` from pool with pool id `id`
     * in chain with chain id `chainId` 
     * This function can only be accessed by account with role POOL.
     * @param id - pool id of pool to withdraw from
     * @param chainId - chain id of chain to withdraw from
     * @param tokenAmount - amount to withdraw
     * @param user - withdraw address
     * @param all - true if withdraw all
     **/
    function withdraw(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount,
        address user,
        bool all
    ) external returns (uint256, uint256);

    /**
     * @notice Sends a withdraw request of amount `tokenAmount` of dead tokens to address `user` from pool with pool id `id`
     * in chain with chain id `chainId`
     * This function can only be accessed by account with role POOL.
     * @param id - pool id of pool to withdraw from
     * @param chainId - chain id of chain to withdraw from
     * @param tokenAmount - amount to withdraw
     * @param user - withdraw address
     * @param all - withdraw all
     **/
    function withdrawDeadTokens(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount,
        address user,
        bool all
    ) external returns (uint256, uint256);

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
    ) external returns (uint256, uint256);

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
     * @notice Sets the status of the collateral usage of a user
     * This function can only be accessed by the account with role POOL.
     * @param user - address of the depositor
     * @param poolId - id of the pool to change the status of
     * @param status - status if true collateral usage is disabled
     **/
    function disableCollateralUsage(
        address user,
        bytes32 poolId,
        bool status
    ) external ;

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
     * @param tokenAmountInSrc - liquidity amount sent from source chain
     * @param tokenAmountInDest - liquidity amount received to destination chain
     **/

    function swap(
        bytes32 id,
        bytes32 srcChainId,
        bytes32 destChainId,
        uint256 tokenAmountInSrc,
        uint256 tokenAmountInDest
    ) external;

     /**
     * @notice Adds pool id to liquidator's token list
     * This function can only be accessed by account with role LIQUIDATION_MANAGER.
     * @param user - address of the liquidator
     * @param id - pool id of the asset.
     **/
    function addTokenForLiquidator(address user, bytes32 id) external;

    /**
     * @notice Removes pool id from borrower's token list
     * This function can only be accessed by account with role LIQUIDATION_MANAGER.
     * @param user - address of the borrower
     * @param id - pool id of the asset.
     **/
    function removeTokenForBorrower(address user, bytes32 id) external;

    /**
     * @notice Refreshes the parameters of the pool.
     * This function is public.
     * @param id - pool id
     * @param chainId - chain id
     **/
    function refresh(bytes32 id, bytes32 chainId) external;

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
     * @notice Reverts if the health factor is not less than MAX_HEALTH_FACTOR, then add the pool to user as collateral
     * @param from - wallet address the user send ceToken.
     * @param to - wallet address the user receive ceToken.
     * * @param to - pool id.
     **/
    function handleTransfer(address from, address to, bytes32 id) external;

    /**
     * @notice Returns list of the tokens the `user` has 
     * @param user - address of the user
     **/
    function getTokens(address user) external view returns (bytes32[] memory);

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
     * @notice Returns total withdrawable balance of an asset for a user
     * @param _poolId - id of the pool.
     * @param _user - address of the user
     **/
    function getWithdrawableBalancePerPool(
        bytes32 _poolId,
        address _user
    ) external view returns (uint256);

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

    /**
     * @notice Get the collateral disabled status
     * @param _user address of the depositor
     * @param _poolId - The pool id .
     **/
    function useAsCollateralDisabled(address _user, bytes32 _poolId) external view returns (bool);

    /**
     * @notice Get the DT scaled amount.
     * @param _poolId - The pool id .
     **/
    function getDTScaled(bytes32 _poolId) external view returns (uint256);

    /**
     * @notice Get the CE scaled amount.
     * @param _poolId - The pool id .
     **/
    function getCEScaled(bytes32 _poolId) external view returns (uint256);

     /**
     * @notice Returns list of pool datas
     * @param _poolIds - ids of the pool.
     **/
    function getPoolData(bytes32[] memory _poolIds) external view returns (Data.PoolData[] memory);


    /**
     * @notice Returns list of config datas
     * @param _poolIds - ids of the pool.
     **/
    function getConfigData(bytes32[] memory _poolIds) external view returns (Data.ConfigData[] memory);
}
