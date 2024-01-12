// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICEToken is IERC20 {
    /**
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/

    function setRoleManager(address roleManagerAddress) external;

    /**
     * @notice Configures core address
     * This function can only be accessed by the account with role SET_CE_TOKEN_METHOD.
     * @param coreAddress - address of the roleManager contract.
     * @param id - The pool id.
     **/
    function setCore(address coreAddress, bytes32 id) external;

    /**
     * @notice Configures reward controller address
     * This function can only be accessed by the account with role SET_CE_TOKEN_METHOD.
     * @param rewardControllerAddress - address of the roleManager contract.
     **/
    function setRewardController(address rewardControllerAddress) external;

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
     * @notice Mints ceToken to address `to`.
     * This function can only be accessed by the account with role MINT_BURN_CE_DEBT_TOKEN.
     * @param to - address of the receipient.
     * @param amount - amount of the token.
     * @param chainId - key for the chain
     **/
    function mintInChain(address to, uint256 amount, bytes32 chainId) external;

    /**
     * @notice Burns ceToken from address `from`.
     * This function can only be accessed by the account with role MINT_BURN_CE_DEBT_TOKEN.
     * @param from - address of the sender.
     * @param amount - amount of the token.
     **/
    function burn(address from, uint256 amount) external;

    /**
     * @notice Burns ceToken to address `from`.
     * This function can only be accessed by the account with role MINT_BURN_CE_DEBT_TOKEN.
     * @param from - address of the sender.
     * @param amount - amount of the token.
     * @param chainId - key for the chain
     **/
    function burnFromChain(
        address from,
        uint256 amount,
        bytes32 chainId
    ) external;

    /**
     * @notice Burns ceToken from address `from` i.e borrower and mints to `to` i.e liquidator
     * This function can only be accessed by the account with role LIQUIDATION_MANAGER.
     * @param from - address of the borrower.
     * @param to - address of liquidator
     * @param amount - amount of the token.
     **/
    function liquidate(address from, address to, uint256 amount) external;

     /**
     * @notice Adds a chain to a dead chain list.
     * This function can only be accessed by the account with role SET_CE_TOKEN_METHOD.
     * @param chainId - chain id of the dead chain
     **/
    function addDeadChain(
       bytes32 chainId
    ) external;


    /**
     * @notice Removes a chain from a dead chain list.
     * This function can only be accessed by the account with role SET_CE_TOKEN_METHOD.
     * @param chainId - chain id of the dead chain
     **/
    function removeDeadChain(
       bytes32 chainId
    ) external;

    /**
     * @notice Returns list of the chains the `user` has its ceTokens on
     * @param user - address of the user
     **/
    function getChains(
       address user
    )  external view returns (bytes32[] memory);

    /**
     * @notice Gets the balance from address `user` before scaled.
     * @param user - address of the user
     **/
    function balanceBeforeScaled(address user) external view returns (uint256);

     /**
     * @notice Gets the scaled CE token balance of the user.
     * @param user - address of the user.
     **/
    function balanceOf(address user) external view returns (uint256);

    /**
     * @notice Gets the balance from address `user` before scaled deducting the dead token balance.
     * @param user - address of the user
     **/
    function balanceBeforeScaledExcludingDeadTokens(
        address user
    ) external view returns (uint256);

    /**
     * @notice Gets the total balance  before scaled excluding dead tokens
     **/
    function totalBalanceBeforeScaledExcludingDeadTokens()
        external
        view
        returns (uint256);

    /**
     * @notice Gets the scaled CE token balance of the user excluding dead tokens
     * @param user - address of the user.
     **/
    function balanceOfExcludingDeadTokens(
        address user
    ) external view returns (uint256);

    /**
     * @notice Gets the total scaled CE token balance
     **/
    function totalBalanceOfExcludingDeadTokens()
        external
        view
        returns (uint256);

    /**
     * @notice Gets the balance of ceToken from address `user` in a particular chain
     * @param user - address of the user
     * @param chainId - key for the chain
     **/
    function balancePerChain(
        address user,
        bytes32 chainId
    ) external view returns (uint256);

    /**
     * @notice Gets the status of the chain
     * @param chainId - key for the chain
     **/
    function isChainDead(bytes32 chainId) external view returns (bool);
}
