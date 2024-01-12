// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface ICedroRewardController {
    /**
     * @notice Interface call to reward controller contract on balance update of a user for calculating cumulative rewards
     * @param user - address of the user
     * @param userBalance - balance of the user
     * @param totalSupply - total balance in the pool
     **/
    function handleReward(
        address user,
        uint256 userBalance,
        uint256 totalSupply
    ) external;
}
