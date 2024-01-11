// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IPool {
    /**
     * @notice Configures role manager address
     * This function can only be accessed by account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/

    function setRoleManager(address roleManagerAddress) external;

    /**
     * @notice Configures fee provider contract.
     * This function can only be accessed by the account with role SET_POOL_METHOD
     * @param feeProviderAddress - address of the fee provider contract.
     **/
    function setFeeProvider(address feeProviderAddress) external;

    /**
     * @notice Configures core contract.
     * This function can only be accessed by the account with role SET_POOL_METHOD
     * @param coreAddress - address of the fee provider contract.
     **/
    function setCore(address coreAddress) external;

    /**
     * @notice Configures adapter contract.
     * This function can only be accessed by the account with role SET_POOL_METHOD
     * @param adapterAddress - address of the adapter contract.
     **/
    function setAdapter(address adapterAddress) external;

    /**
     * @notice Sets the status of the collateral usage of the depositor
     * This function can only be accessed by the account with role POOL.
     * @param poolId - id of the pool to change the status of
     * @param status - status if true collateral usage is disabled
     **/
    function disableCollateralUsage(
        bytes32 poolId,
        bool status
    ) external;

    /**
     * @notice Sends a withdraw request of amount `ceAmount` to address `to` from pool with pool id `id`
     * in chain with chain id `chainId` to core contract
     * This function can be accessed by anyone
     * @param id - pool id of pool to withdraw from
     * @param chainId - chain id of chain to withdraw from
     * @param tokenAmount - amount to withdraw
     * @param to - withdraw address
     * @param route - communication protocol
     * @param airdropAmount - amount to be airdropped to destination chain
     * @param all - true if withdraw all
     **/
    function withdraw(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount,
        bytes32 to,
        bytes32 route,
        uint256 airdropAmount,
        bool all
    ) external;

    /**
     * @notice Sends a borrow request of amount `tokenAmount` to address `to` from pool with pool id `id`
     * in chain with chain id `chainId` to core contract
     * This function can be accessed by anyone
     * @param id - pool id of pool to borrow from
     * @param chainId - chain id of chain to borrow from
     * @param tokenAmount - amount to borrow
     * @param to - borrow address
     * @param route - communication protocol
     * @param airdropAmount - amount to be airdropped to destination chain
     **/
    function borrow(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount,
        bytes32 to,
        bytes32 route,
        uint256 airdropAmount
    ) external;

    /**
     * @notice Leverager method looping deposit and borrow of an asset
     * This function can be accessed by anyone
     * @param id - pool id of pool to borrow from
     * @param chainId - chain id of chain to borrow from
     * @param tokenAmount - total amount to loop
     * @param borrowRatio - ratio of tokens to borrow
     * @param loopCount - repeat count for loop
     **/
    function loop(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount,
        uint256 borrowRatio,
        uint256 loopCount
    ) external;

    /**
     * @notice Swaps liquidity amount from one chain to another
     * This function can only be accessed by account with role SWAP.
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
     * @notice Executes the function according to the request type in the payload
     * This function can only be accessed by the account with role ADAPTER
     * @param payload - information of pool id, user and token amount
     * @param chainId - chain id of the source chain
     * @param route - communication protocol through which payload is received
     **/
    function execute(bytes memory payload, bytes32 chainId, bytes32 route) external;

    /**
     * @notice Configures fee status.
     * This function can only be accessed by the account with role SET_POOL_METHOD
     **/
    function toggleFeeEnable() external;

     /**
     * @notice Configures reward status.
     * This function can only be accessed by the account with role SET_POOL_METHOD
     **/ 
    function toggleRewardEnable() external;

    /**
     * @notice Configures pool status for withdraw
     * This function can only be accessed by the account with role PROTOCOL_PAUSE
     * @param id - pool id of the asset.
     * @param chainId - id of the chain to withdraw asset from.
     * @param status - status of the pool.
     **/
    function setWithdrawPause(
        bytes32 id,
        bytes32 chainId,
        bool status
    ) external;

    /**
     * @notice Configures pool status for borrow
     * This function can only be accessed by the account with role PROTOCOL_PAUSE
     * @param id - pool id of the asset.
     * @param chainId - id of the chain to borrow asset from.
     * @param status - status of the pool.
     **/
    function setBorrowPause(bytes32 id, bytes32 chainId, bool status) external;

    /**
     * @notice Toggles the status of the protocol on and off.
     * This function can only be accessed by the account with role PROTOCOL_PAUSE

     **/
    function toggleProtocolStatus() external;
}
