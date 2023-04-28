// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IPool {
    /**
     * @notice Configures role manager address
     * This function can only be accessed by the owner.
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
     * @notice Sends a withdraw request of amount `ceAmount` to address `to` from pool with pool id `id`
     * in chain with chain id `chainId` to core contract
     * This function can be accessed by anyone
     * @param id - pool id of pool to withdraw from
     * @param chainId - chain id of chain to withdraw from
     * @param ceAmount - amount to withdraw
     * @param to - withdraw address
     * @param route - communication protocol
     * @param airdropAmount - amount to be airdropped to destination chain
     **/
    function withdraw(
        bytes32 id,
        bytes32 chainId,
        uint256 ceAmount,
        bytes32 to,
        bytes32 route,
        uint256 airdropAmount
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
     * @notice Executes the function according to the request type in the payload
     * This function can only be accessed by the account with role ADAPTER
     * @param payload - information of pool id, user and token amount
     * @param chainId - chain id of the source chain
     **/
    function execute(bytes memory payload, bytes32 chainId) external;

    /**
     * @notice Configures fee status.
     * This function can only be accessed by the account with role SET_POOL_METHOD
     **/
    function toggleFeeEnable() external;

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
