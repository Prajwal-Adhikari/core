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
    mapping(address => mapping(bytes32 => uint256)) public balancePerChain;
    mapping(address => bytes32[]) public chains;
    bytes32[] public deadChains;
    mapping(bytes32 => bool) public isChainDead;


    error TransferTooSoonAfterMint(
        uint256 currentBlock,
        uint256 expectToExceedBlock
    );
    error UserIsCaged(address toUser);
    error BurnTooSoonAfterMint(
        uint256 currentBlock,
        uint256 expectToExceedBlock
    );
    error NotEnoughAmountInChain(address fromUser, bytes32 chainId);
    error DeadChain(bytes32 chainId);
    error NotEnoughCeTokens(address user);

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
        __ERC20_init(name_, symbol_);
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

        uint256 ceTokenBalance = super.balanceOf(from);
        uint256 amountPerChain;
        uint ceScaled = ICore(core).getCEScaled(poolId);
        uint256 ceAmount = amount.mul(1e18).div(ceScaled);
        bytes32[] memory chainIds = chains[from];

        super._transfer(from, to, ceAmount);
        ICore(core).handleTransfer(from, to, poolId);

        for (uint256 i; i < chainIds.length; i++) {
            amountPerChain = balancePerChain[from][chainIds[i]].mul(ceAmount).div(ceTokenBalance);
            balancePerChain[from][chainIds[i]] -= amountPerChain;
            balancePerChain[to][chainIds[i]] += amountPerChain;
            _addChain(to, chainIds[i]);
        }
    }

    /**
     * @notice Get the balance from address `user` before scaled.
     * @param user - address of the user
     **/
    function balanceBeforeScaled(address user) external view returns (uint256) {
        return super.balanceOf(user);
    }

    function balanceBeforeScaledExcludingDeadTokens(
        address user
    ) public view returns (uint256) {
        uint256 deadBalance;
        for (uint256 i; i < deadChains.length; i++) {
            deadBalance += balancePerChain[user][deadChains[i]];
        }
        return super.balanceOf(user).sub(deadBalance);
    }

    /**
     * @dev Gets the sclaed CE token balance of user.
     * @param user - The address of user.
     **/

    function balanceOf(address user) public view override returns (uint256) {
        uint ceScaled = ICore(core).getCEScaled(poolId);
        return (super.balanceOf(user) * ceScaled) / 1e18;
    }

    function mintInChain(
        address to,
        uint256 amount,
        bytes32 chainId
    ) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        // require(
        //     transferBlockRelease[to] != 2 ** 256 - 1,
        //     string.concat(TAG,": User is already caged")
        // );

        if (transferBlockRelease[to] == 2 ** 256 - 1) revert UserIsCaged(to);

        if (amount > lockupTriggerAmt) {
            transferBlockRelease[to] = block.number + transferBlockWait;
        }
        balancePerChain[to][chainId] = amount;
        _addChain(to, chainId);
        _mint(to, amount);
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
        uint256 ceTokenBalance = super.balanceOf(to);
        bytes32[] memory chainIds = chains[to];

        for (uint256 i; i < chainIds.length; i++) {
            balancePerChain[to][chainIds[i]] += balancePerChain[to][chainIds[i]]
                .mul(amount)
                .div(ceTokenBalance);
        }

        _mint(to, amount);
    }

    function burnFromChain(
        address from,
        uint256 amount,
        bytes32 chainId
    ) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        // require(
        //     block.number > transferBlockRelease[from],
        //     string.concat(TAG,": burn too soon after cross-chain mint")
        // );
        if (block.number <= transferBlockRelease[from])
            revert BurnTooSoonAfterMint(
                block.number,
                transferBlockRelease[from]
            );

        if (balancePerChain[from][chainId] < amount)
            revert NotEnoughAmountInChain(from, chainId);

        balancePerChain[from][chainId] -= amount;
        if (balancePerChain[from][chainId] == 0) 
            _removeChain(from, chainId);

        _burn(from, amount);
    }

    function burn(
        address from,
        uint256 amount
    ) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        // require(
        //     block.number > transferBlockRelease[from],
        //     string.concat(TAG,": burn too soon after cross-chain mint")
        // );
        if (block.number <= transferBlockRelease[from])
            revert BurnTooSoonAfterMint(
                block.number,
                transferBlockRelease[from]
            );

        uint256 ceTokenBalance = balanceBeforeScaledExcludingDeadTokens(from);
        if (ceTokenBalance == 0)
            revert NotEnoughCeTokens(from);
        uint256 amountPerChain;
        bytes32[] memory chainIds = chains[from];

        for (uint256 i; i < chainIds.length; i++) {
            if (!isChainDead[chainIds[i]]){
                amountPerChain = balancePerChain[from][chainIds[i]].mul(amount).div(ceTokenBalance);
                if (balancePerChain[from][chainIds[i]] < amountPerChain)
                    revert NotEnoughAmountInChain(from,chainIds[i]);
                balancePerChain[from][chainIds[i]] -= amountPerChain;
            }
        }

        _burn(from, amount);
    }

    function liquidate(
        address from,
        address to,
        uint256 amount
    ) external onlyRole(IRoleManager(roleManager).LIQUIDATION_MANAGER()) {

        uint256 ceTokenBalance = balanceBeforeScaledExcludingDeadTokens(from);
        uint256 amountPerChain;
        bytes32[] memory chainIds = chains[from];

        for (uint256 i; i < chainIds.length; i++) {
            if (!isChainDead[chainIds[i]]){
                amountPerChain = balancePerChain[from][chainIds[i]].mul(amount).div(ceTokenBalance);
                balancePerChain[from][chainIds[i]] -= amountPerChain;
                balancePerChain[to][chainIds[i]] += amountPerChain;
                _addChain(to, chainIds[i]);
            }
        }
        _burn(from, amount);
        _mint(to,amount);
    }

    function _addChain(address user, bytes32 chainId) internal {
        for (uint256 i; i < chains[user].length; i++) {
            if (chains[user][i] == chainId) {
                return;
            }
        }
        chains[user].push(chainId);
    }

    function _removeChain(address user, bytes32 chainId) internal {
        uint len = chains[user].length;
        for (uint256 i; i < len; i++) {
            if (chains[user][i] == chainId) {
                chains[user][i] = chains[user][len - 1];
                chains[user].pop();
                break;
            }
        }
    }

    function addDeadChain(
       bytes32 chainId
    ) external onlyRole(IRoleManager(roleManager).SET_CE_TOKEN_METHOD()) {
        if (isChainDead[chainId])
            revert DeadChain(chainId);
        deadChains.push(chainId);
        isChainDead[chainId] = true;
    }

    function removeDeadChain(
       bytes32 chainId
    ) external onlyRole(IRoleManager(roleManager).SET_CE_TOKEN_METHOD()) {
        uint len = deadChains.length;
        for (uint256 i; i < len; i++) {
            if (deadChains[i] == chainId) {
                deadChains[i] = deadChains[len - 1];
                deadChains.pop();
                isChainDead[chainId] = false;
                break;
            }
        }
    }
    function getChains(
       address user
    ) public view returns (bytes32[] memory){
        return chains[user];
    }
}
