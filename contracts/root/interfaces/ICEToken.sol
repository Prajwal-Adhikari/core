// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICEToken is IERC20 {
    /**
     * @notice Configures role manager address
     * This function can only be accessed by the owner.
     * @param roleManagerAddress - address of the roleManager contract.
     **/

    function setRoleManager(address roleManagerAddress) external;

    /**
     * @notice Configures core address
     * This function can only be accessed by the account with role SET_CE_TOKEN_METHOD.
     * @param coreAddress - address of the roleManager contract.
     **/

    function setCore(address coreAddress) external;

    /**
     * @notice Configures a waiting period before transfer if
     * the mint amount exceeds lockup trigger amount
     * This function can only be accessed by the account with role SET_CE_TOKEN_METHOD.
     * @param num - number of blocks to wait.
     **/
    function setTransferBlockWait(uint256 num) external;

    /**
     * @notice Configures the release period for user before transfer
     * This function can only be accessed by the account with role CONTROLLER.
     * @param user - address of a user
     * @param blockNumber - number of the block upto which transfer is freezed
     **/
    function setTransferBlockRelease(
        address user,
        uint256 blockNumber
    ) external;

    /**
     * @notice Configures amount when exceeded triggers the lock up.
     * This function can only be accessed by the account with role SET_CE_TOKEN_METHOD.
     * @param amount - amount of the token.
     **/

    function setLockupTriggerAmount(uint256 amount) external;

    /**
     * @notice Mints ceToken to address `to`.
     * This function can only be accessed by the account with role MINT_BURN_CE_DEBT_TOKEN.
     * @param to - address of the receipient.
     * @param amount - amount of the token.
     **/
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burns ceToken from address `from`.
     * This function can only be accessed by the account with role MINT_BURN_CE_DEBT_TOKEN.
     * @param from - address of the sender.
     * @param amount - amount of the token.
     **/
    function burn(address from, uint256 amount) external;

    /**
     * @notice Get the balance from address `user` before scaled.
     * @param user - address of the user
     **/
    function balanceBeforeScaled(address user) external view returns (uint256);
}
