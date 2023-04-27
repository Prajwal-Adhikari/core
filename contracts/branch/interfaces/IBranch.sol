// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/// @title A LayerZero example sending a cross chain message from a source chain to a destination chain to increment a counter
interface IBranch {

    /**
     * @notice Configures role manager address
     * This function can only be accessed by the owner.
     * @param roleManagerAddress - address of the roleManager contract.
     **/

    /**
     * @notice Configures pool for an asset
     * This function can only be accessed by account with role SET_POOL.
     * @param id - pool id for the asset.
     * @param token - address of the asset.
     * @param enable - status of the pool
     **/
    function setPool(bytes32 id, address token, bool enable) external;

    /**
     * @notice Configures adapter contract.
     * This function can only be accessed by account with role SET_BRANCH_METHOD.
     * @param adapterAddress - address of the adapter contract.
     **/
    function setAdapter(address adapterAddress) external;

    /**
     * @notice Configures router address for swap.
     * This function can only be accessed by account with role SET_BRANCH_METHOD.
     * @param routerAddress - address of the  Stargate router contract.
     * @param vaultAddress - address of the  Stargate vault contract.
     **/
    function setStargateRouterAndVault(
        address routerAddress,
        address vaultAddress
    ) external;

    /**
     * @notice Configures pool status for deposit
     * This function can only be accessed by account with role PROTOCOL_PAUSE.
     * @param id - pool id of the asset.
     * @param status - status of the pool.
     **/
    function setDepositPause(bytes32 id, bool status) external;

    /**
     * @notice Configures pool status for repay
     * This function can only be accessed by account with role PROTOCOL_PAUSE.
     * @param id - pool id of the asset.
     * @param status - status of the pool.
     **/
    function setRepayPause(bytes32 id, bool status) external;

    /**
     * @notice Toggles the status of the protocol on and off.
     * This function can only be accessed by account with role PROTOCOL_PAUSE.

     **/
    function toggleProtocolStatus() external;

    /**
     * @notice Toggles the status of the swap through Stargate
     * This function can only be accessed by account with role SWAP.

     **/

    function toggleSwapStatus() external;

    /**
     * @notice Configures name of the chain corresponding to chain id.
     * This function can only be accessed by account with role SET_BRANCH_METHOD.
     * @param chain - name of the chain.
     * @param id - chain id of the chain.
     **/
    function setChainName(bytes32 chain, uint16 id) external;

    /**
     * @notice Sends deposit information message to the Root.
     * This function can be accessed by the user.
     * @param id - pool id of the pool of the deposited amount
     * @param amount - amount deposited in the pool
     * @param route - communication protocol
     * @param  airdropAmount - amount to be airdropped to destination chain
     **/
    function depositRequest(
        bytes32 id,
        uint256 amount,
        bytes32 route,
        uint256 airdropAmount
    ) external payable;

    /**
     * @notice Sends repay information message to the Root.
     * This function can be accessed by the user.
     * @param id - pool id of the pool of the repaid amount
     * @param amount - amount repaid in the pool
     * @param route - communication protocol
     * @param  airdropAmount - amount to be airdropped to destination chain
     **/
    function repayRequest(
        bytes32 id,
        uint256 amount,
        bytes32 route,
        uint256 airdropAmount
    ) external payable;

    /**
     * @notice Swaps liquidity across chain
     * This function can only be accessed by account with role SWAP.
     * @param qty - amount to be swapped
     * @param id - id of the pool
     * @param dstChainId - chain id of destination
     * @param srcPoolId - pool id of source token in Stargate
     * @param dstPoolId - pool id of destination token in Stargate
     * @param destination - address of the receiver
     * @param route - communication protocol
     * @param fee - communication protocol fee
     **/
    function swapRequest(
        uint256 qty,
        bytes32 id,
        uint16 dstChainId,
        uint16 srcPoolId,
        uint16 dstPoolId,
        address destination,
        bytes32 route,
        uint256 fee
    ) external payable;

    /**
     * @notice emergency function to withdraw liquidity
     * This function can only be accessed by account with role EMERGENCY_WITHDRAW.
     * @param id - token address to withdraw
     * @param amount - amount of token to withdraw
     * @param to - receipient address
     **/
    function emergencyWithdraw(bytes32 id, uint256 amount, address to) external;

    /**
     * @notice Transfers token to the user.
     * This function can only be accessed by account with role ADAPTER.
     * @param payload - information containing token amount and receipient.
     **/
    function transferToken(bytes memory payload) external;
}
