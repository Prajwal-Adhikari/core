// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "../interfaces/IRoleManager.sol";
import "../interfaces/ICore.sol";
import "../interfaces/ICedroRewardController.sol";

string constant TAG = "DebtToken";

/**
 * @title Debt (DT) Token
 * @notice Each token that is deposited will have it's own DT Token.
 **/
contract DebtToken is ERC20Upgradeable {
    using SafeMathUpgradeable for uint256;

    address public core;
    address public roleManager;
    address public rewardController;
    bytes32 public poolId;

    error CannotTransferDebtToken(string contractTAG);
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initilize the contract.
     * @param name_ - The token name.
     * @param symbol_ - The token symbol.
     * @param roleManagerAddress - The EOA of role manager.
     **/
    function initialize(
        string memory name_,
        string memory symbol_,
        address roleManagerAddress
    ) public initializer {
        __ERC20_init( name_, symbol_);
        roleManager = roleManagerAddress;
    }

    /**
     * @dev Modifier that checks if caller has a specific role.
     **/
    modifier onlyRole(bytes32 role) {
        IRoleManager(roleManager).checkRole(role, _msgSender());
        _;
    }

    /**
     * @notice Configures core address
     * This function can only be accessed by the account with role SET_CE_TOKEN_METHOD.
     * @param coreAddress - address of the roleManager contract.
     * @param id - The pool id.
     **/
    function setCore(
        address coreAddress,
        bytes32 id
    ) external onlyRole(IRoleManager(roleManager).SET_CE_TOKEN_METHOD()) {
        core = coreAddress;
        poolId = id;
    }

    /**
     * @notice Configures reward controller address
     * This function can only be accessed by the account with role SET_CE_TOKEN_METHOD.
     * @param rewardControllerAddress - address of the roleManager contract.
     **/
    function setRewardController(address rewardControllerAddress) external onlyRole(IRoleManager(roleManager).SET_CE_TOKEN_METHOD()) {
        rewardController = rewardControllerAddress;

    }

    /**
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/
    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    /**
     * @notice Get the balance from address `user` before scaled.
     * @param user - address of the user
     **/
    function balanceBeforeScaled(address user) external view returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @dev Gets the sclaed DT token balance.
     * @param user - The address of user.
     **/
    function balanceOf(address user) public view override returns (uint256) {
        uint256 dtScaled = ICore(core).getDTScaled(poolId);
        return super.balanceOf(user).mul(dtScaled).div(1e18);
    }

    /**
     * @dev Transfer DT token.
     * @param from - The address of sender.
     * @param to - The address of receiver.
     * @param amount - The transfer amount.
     **/
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal pure override {
        (from, to, amount);
        revert CannotTransferDebtToken(TAG);
    }

    /**
     * @notice Mints debtToken to address `to`.
     * This function can only be accessed by account with role MINT_BURN_CE_DEBT_TOKEN.
     * @param to - address of the receipient.
     * @param amount - amount of the token.
     **/
    function mint(address to, uint256 amount) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        _handleReward(to);
        _mint(to, amount);
    }

    /**
     * @notice Burns debtToken from address `from`.
     * This function can only be accessed by account with role MINT_BURN_CE_DEBT_TOKEN.
     * @param from - address of the sender.
     * @param amount - amount of the token.
     **/
    function burn(address from, uint256 amount) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        _handleReward(from);
        _burn(from, amount);
    }

    function _handleReward(address user) internal {
        if(rewardController != address(0)){
            uint256 userBalance = super.balanceOf(user);
            uint256 currentTotalBalance  = super.totalSupply();
            ICedroRewardController(rewardController).handleReward(user, userBalance, currentTotalBalance);
        }
    }
}
