// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "../interfaces/IRoleManager.sol";
import "../interfaces/ICore.sol";

/**
 * @title CE Token
 * @notice Each token that is deposited will have it's own CE Token.
 * @notice CE Token is the equivalent to Liquidity Pool(LP) Token.
 **/
contract CEToken is ERC20Upgradeable {
    using SafeMathUpgradeable for uint256;
    address public core;
    address public roleManager;
    bytes32 public poolId;
    uint256 public transferBlockWait; //amount of blocks to wait before user can transfer minted ceToken
    uint256 public lockupTriggerAmt; //amount where lockup will kick in after cross-chain transfer
    mapping(address => uint256) public transferBlockRelease; //Block number

    error TransferTooSoonAfterMint(uint256 currentBlock, uint256 expectToExceedBlock);
    error UserIsCaged(address toUser);
    error BurnTooSoonAfterMint(uint256 currentBlock, uint256 expectToExceedBlock);
    
    /**
     * @dev Modifier that checks if caller has a specific role.
     **/
    modifier onlyRole(bytes32 role) {
        IRoleManager(roleManager).checkRole(role, _msgSender());
        _;
    }

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
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/
    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    /**
     * @notice Configures core address
     * This function can only be accessed by the account with role SET_CE_TOKEN_METHOD.
     * @param coreAddress - address of the roleManager contract.
     **/
    function setCore(
        address coreAddress,
        bytes32 id
    ) external onlyRole(IRoleManager(roleManager).SET_CE_TOKEN_METHOD()) {
        core = coreAddress;
        poolId = id;
    }

    /**
     * @notice Configures a waiting period before transfer if
     * the mint amount exceeds lockup trigger amount
     * This function can only be accessed by the account with role SET_CE_TOKEN_METHOD.
     * @param num - number of blocks to wait.
     **/
    function setTransferBlockWait(uint256 num) external onlyRole(IRoleManager(roleManager).SET_CE_TOKEN_METHOD()) {
        transferBlockWait = num;
    }

    /**
     * @notice Configures the release period for user before transfer
     * This function can only be accessed by the account with role CONTROLLER.
     * @param user - address of a user
     * @param blockNumber - number of the block upto which transfer is freezed
     **/
    function setTransferBlockRelease(
        address user,
        uint256 blockNumber
    ) external onlyRole(IRoleManager(roleManager).CONTROLLER()) {
        transferBlockRelease[user] = blockNumber;
    }

    /**
     * @notice Configures amount when exceeded triggers the lock up.
     * This function can only be accessed by the account with role SET_CE_TOKEN_METHOD.
     * @param amount - amount of the token.
     **/
    function setLockupTriggerAmount(uint256 amount) external onlyRole(IRoleManager(roleManager).SET_CE_TOKEN_METHOD()) {
        lockupTriggerAmt = amount;
    }

    /**
     * @dev Transfer CE token.
     * @param from - The address of sender.
     * @param to - The address of receiver.
     * @param amount - The transfer amount.
     **/
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if(block.number <= transferBlockRelease[from])
            revert TransferTooSoonAfterMint(block.number, transferBlockRelease[from]);

        uint ceScaled = ICore(core).getCEScaled(poolId);
        super._transfer(from, to, amount.mul(1e18).div(ceScaled));
        ICore(core).handleTransfer(from, to, poolId);
    }

    /**
     * @notice Get the balance from address `user` before scaled.
     * @param user - address of the user
     **/
    function balanceBeforeScaled(address user) external view returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @dev Gets the sclaed CE token balance of user.
     * @param user - The address of user.
     **/
    function balanceOf(address user) public view override returns (uint256) {
        uint ceScaled = ICore(core).getCEScaled(poolId);
        return super.balanceOf(user) * ceScaled / 1e18;
    }

    /**
     * @notice Mints ceToken to address `to`.
     * This function can only be accessed by the account with role MINT_BURN_CE_DEBT_TOKEN.
     * @param to - address of the receipient.
     * @param amount - amount of the token.
     **/
    function mint(address to, uint256 amount) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        if( transferBlockRelease[to] == 2 ** 256 - 1)
            revert UserIsCaged(to);

        if (amount > lockupTriggerAmt) {
            transferBlockRelease[to] = block.number + transferBlockWait;
        }
        _mint(to, amount);
    }

    /**
     * @notice Burns ceToken from address `from`.
     * This function can only be accessed by the account with role MINT_BURN_CE_DEBT_TOKEN.
     * @param from - address of the sender.
     * @param amount - amount of the token.
     **/
    function burn(address from, uint256 amount) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        if(block.number <= transferBlockRelease[from])
            revert BurnTooSoonAfterMint(block.number, transferBlockRelease[from]);

        _burn(from, amount);
    }

}
