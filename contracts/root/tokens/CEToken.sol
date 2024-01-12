// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "../interfaces/IRoleManager.sol";
import "../interfaces/ICore.sol";
import "../interfaces/ICedroRewardController.sol";

string constant TAG = "CEToken";

/**
 * @title CE Token
 * @notice Each token that is deposited will have it's own CE Token.
 * @notice CE Token is the equivalent to Liquidity Pool(LP) Token.
 **/
contract CEToken is ERC20Upgradeable {
    using SafeMathUpgradeable for uint256;
    address public core;
    address public roleManager;
    address public rewardController;
    bytes32 public poolId;
    uint256 public transferBlockWait; //amount of blocks to wait before user can transfer minted ceToken
    uint256 public lockupTriggerAmt; //amount where lockup will kick in after cross-chain transfer
    mapping(address => uint256) public transferBlockRelease; //Block number
    mapping(address => mapping(bytes32 => uint256)) public balancePerChain; // user => chain => balance
    mapping(bytes32 => uint256) public totalBalancePerChain; // chain => balance
    mapping(address => bytes32[]) public chains; //chainList of a user holding the asset from different chains
    mapping(address => mapping(bytes32 => bool)) public isChainInList;
    bytes32[] public deadChains;
    mapping(bytes32 => bool) public isChainDead;

    error TransferTooSoonAfterMint(
        string contractTAG,
        uint256 currentBlock,
        uint256 releaseBlock
    );
    error UserIsCaged(string contractTAG, address toUser);
    error BurnTooSoonAfterMint(
        string contractTAG,
        uint256 currentBlock,
        uint256 releaseBlock
    );
    error NotEnoughAmountInChain(string contractTAG, address user, bytes32 chainId);
    error DeadChain(string contractTAG, bytes32 chainId);
    error NotEnoughCeTokens(string contractTAG, address user);
    error InsufficientBalance(string contractTAG, address user);

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
     * @param id - pool id.
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
     * @notice Overrides internal transfer of CE token.
     * @param from - The address of sender.
     * @param to - The address of receiver.
     * @param amount - The transfer amount in scaled form
     **/
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if(block.number <= transferBlockRelease[from])
            revert TransferTooSoonAfterMint(TAG, block.number, transferBlockRelease[from]);

        uint256 ceTokenBalance = super.balanceOf(from);
        if (ceTokenBalance == 0){
            revert InsufficientBalance(TAG, from);
        }
        uint256 amountPerChain;
        uint256 ceScaled = ICore(core).getCEScaled(poolId);
        uint256 ceAmount = amount.mul(1e18).div(ceScaled);
        bytes32[] memory chainIds = chains[from];
        _handleReward(from,to);
       

        for (uint256 i; i < chainIds.length; i++) {
            amountPerChain = balancePerChain[from][chainIds[i]].mul(ceAmount).div(ceTokenBalance);
            balancePerChain[from][chainIds[i]] -= amountPerChain;
            balancePerChain[to][chainIds[i]] += amountPerChain;
            if (balancePerChain[from][chainIds[i]] == 0)
                _removeChain(from, chainIds[i]);
            _addChain(to, chainIds[i]);
        }

        super._transfer(from, to, ceAmount);

        ICore(core).handleTransfer(from, to, poolId);
    }

    /**
     * @notice Gets the balance from address `user` before scaled.
     * @param user - address of the user
     **/
    function balanceBeforeScaled(address user) public view returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @notice Gets the scaled CE token balance of the user.
     * @param user - address of the user.
     **/
    function balanceOf(address user) public view override returns (uint256) {
        uint256 ceScaled = ICore(core).getCEScaled(poolId);
        return (super.balanceOf(user).mul(ceScaled)).div(1e18);
    }

    /**
     * @notice Gets the balance from address `user` before scaled excluding dead tokens
     * @param user - address of the user
     **/
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
     * @notice Gets the total balance  before scaled excluding dead tokens
     **/
    function totalBalanceBeforeScaledExcludingDeadTokens() public view returns (uint256) {
        uint256 deadBalance;
        for (uint256 i; i < deadChains.length; i++) {
            deadBalance += totalBalancePerChain[deadChains[i]];
        }
        return super.totalSupply().sub(deadBalance);
    }
    
    /**
     * @notice Gets the scaled CE token balance of the user excluding dead tokens
     * @param user - address of the user.
     **/
    function balanceOfExcludingDeadTokens(
        address user
    ) public view returns (uint256) {
        uint256 ceScaled = ICore(core).getCEScaled(poolId);
        return (balanceBeforeScaledExcludingDeadTokens(user).mul(ceScaled)).div(1e18);
    }

    /**
     * @notice Gets the total scaled CE token balance
     **/
    function totalBalanceOfExcludingDeadTokens() public view returns (uint256) {
        uint256 ceScaled = ICore(core).getCEScaled(poolId);
        return (totalBalanceBeforeScaledExcludingDeadTokens().mul(ceScaled)).div(1e18);
    }

    
    /**
     * @notice Mints ceToken to address `to` in chain with chain id `chainId` during deposit or repay(when excess)
     * This function can only be accessed by the account with role MINT_BURN_CE_DEBT_TOKEN.
     * @param to - address of the receipient.
     * @param amount - amount of the token.
     * @param chainId - chain id of chain in which the token is minted to
     **/
    function mintInChain(
        address to,
        uint256 amount,
        bytes32 chainId
    ) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        if (transferBlockRelease[to] == 2 ** 256 - 1) 
            revert UserIsCaged(TAG, to);
        if (amount > lockupTriggerAmt) {
            transferBlockRelease[to] = block.number + transferBlockWait;
        }
        _handleReward(to,to);
        balancePerChain[to][chainId] += amount;
        totalBalancePerChain[chainId] += amount;
        _addChain(to, chainId);
        _mint(to, amount);
    }

    /**
     * @notice Mints ceToken to address `to` during interest distribution proportionately accross chains
     * This function can only be accessed by the account with role MINT_BURN_CE_DEBT_TOKEN.
     * @param to - address of the receipient.
     * @param amount - amount of the token.
     **/
    function mint(address to, uint256 amount) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        if( transferBlockRelease[to] == 2 ** 256 - 1)
            revert UserIsCaged(TAG, to);
        if (amount > lockupTriggerAmt) {
            transferBlockRelease[to] = block.number + transferBlockWait;
        }

        _handleReward(to,to);
        uint256 ceTokenBalance = super.balanceOf(to);
        bytes32[] memory chainIds = chains[to];
        uint256 amountPerChain;

        for (uint256 i; i < chainIds.length; i++) {
            amountPerChain = balancePerChain[to][chainIds[i]].mul(amount).div(ceTokenBalance);
            balancePerChain[to][chainIds[i]] += amountPerChain;
            totalBalancePerChain[chainIds[i]] += amountPerChain;
        }
        _mint(to, amount);
    }

    /**
     * @notice Burns ceToken from address `from` from chain with chain id `chainId` during withdraw if asset is available in the chain
     * This function can only be accessed by the account with role MINT_BURN_CE_DEBT_TOKEN.
     * @param from - address of the sender.
     * @param amount - amount of the token.
     * @param chainId - chain id of chain from which the token is burned from
     **/
    function burnFromChain(
        address from,
        uint256 amount,
        bytes32 chainId
    ) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        if (block.number <= transferBlockRelease[from])
            revert BurnTooSoonAfterMint(
                TAG,
                block.number,
                transferBlockRelease[from]
            );

        if (balancePerChain[from][chainId] < amount)
            revert NotEnoughAmountInChain(TAG, from, chainId);

        _handleReward(from,from);
        balancePerChain[from][chainId] -= amount;
        totalBalancePerChain[chainId] -= amount;
        if (balancePerChain[from][chainId] == 0) 
            _removeChain(from, chainId);

        _burn(from, amount);
    }

    /**
     * @notice Burns ceToken from address `from` proportionately accross chains
     * This function can only be accessed by the account with role MINT_BURN_CE_DEBT_TOKEN.
     * @param from - address of the sender.
     * @param amount - amount of the token.
     **/
    function burn(
        address from,
        uint256 amount
    ) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        if (block.number <= transferBlockRelease[from])
            revert BurnTooSoonAfterMint(
                TAG,
                block.number,
                transferBlockRelease[from]
            );

        uint256 ceTokenBalance = balanceBeforeScaledExcludingDeadTokens(from);
        if (ceTokenBalance == 0)
            revert NotEnoughCeTokens(TAG, from);

        _handleReward(from,from);
        uint256 amountPerChain;
        bytes32[] memory chainIds = chains[from];

        for (uint256 i; i < chainIds.length; i++) {
            if (!isChainDead[chainIds[i]]){
                amountPerChain = balancePerChain[from][chainIds[i]].mul(amount).div(ceTokenBalance);
                if (balancePerChain[from][chainIds[i]] < amountPerChain)
                    revert NotEnoughAmountInChain(TAG, from,chainIds[i]);
                balancePerChain[from][chainIds[i]] -= amountPerChain;
                totalBalancePerChain[chainIds[i]] -= amountPerChain;
                if (balancePerChain[from][chainIds[i]] == 0) 
                    _removeChain(from, chainIds[i]);
            }
        }

        _burn(from, amount);
    }

    /**
     * @notice Liquidates ceToken from borrower `from` to liquidator `to`.
     * This function can only be accessed by the account with role LIQUIDATION_MANAGER.
     * @param from - address of the borrower.
     * @param to - address of the liquidator.
     * @param amount - amount of the token to be liquidated (ceAmount)
     **/
    function liquidate(
        address from,
        address to,
        uint256 amount
    ) external onlyRole(IRoleManager(roleManager).LIQUIDATION_MANAGER()) {

        uint256 amountPerChain;
        bytes32[] memory chainIds = chains[from];

        _handleReward(from, to);
        uint256 ceTokenBalance = balanceBeforeScaledExcludingDeadTokens(from);
        for (uint256 i; i < chainIds.length; i++) {
            if (!isChainDead[chainIds[i]]){
                amountPerChain = balancePerChain[from][chainIds[i]].mul(amount).div(ceTokenBalance);
                if (balancePerChain[from][chainIds[i]] < amountPerChain)
                    revert NotEnoughAmountInChain(TAG, from,chainIds[i]);
                balancePerChain[from][chainIds[i]] -= amountPerChain;
                balancePerChain[to][chainIds[i]] += amountPerChain;
                if (balancePerChain[from][chainIds[i]] == 0)
                    _removeChain(from, chainIds[i]);
                _addChain(to, chainIds[i]);
            }
        }

        super._transfer(from, to, amount);
    }

    /**
     * @notice Adds a chain to a dead chain list.
     * This function can only be accessed by the account with role SET_CE_TOKEN_METHOD.
     * @param chainId - chain id of the dead chain
     **/
    function addDeadChain(
       bytes32 chainId
    ) external onlyRole(IRoleManager(roleManager).SET_CE_TOKEN_METHOD()) {
        if (isChainDead[chainId])
            revert DeadChain(TAG, chainId);
        deadChains.push(chainId);
        isChainDead[chainId] = true;
    }

    /**
     * @notice Removes a chain from a dead chain list.
     * This function can only be accessed by the account with role SET_CE_TOKEN_METHOD.
     * @param chainId - chain id of the dead chain
     **/
    function removeDeadChain(
       bytes32 chainId
    ) external onlyRole(IRoleManager(roleManager).SET_CE_TOKEN_METHOD()) {
        uint256 len = deadChains.length;
        for (uint256 i; i < len; i++) {
            if (deadChains[i] == chainId) {
                deadChains[i] = deadChains[len - 1];
                deadChains.pop();
                isChainDead[chainId] = false;
                break;
            }
        }
    }

    /**
     * @notice Returns list of the chains the `user` has its ceTokens on
     * @param user - address of the user
     **/
    function getChains(
       address user
    ) public view returns (bytes32[] memory){
        return chains[user];
    }

    function _addChain(address user, bytes32 chainId) internal {
        if (isChainInList[user][chainId])
            return;
        isChainInList[user][chainId] = true;
        chains[user].push(chainId);
    }

    function _removeChain(address user, bytes32 chainId) internal {
        uint256 len = chains[user].length;
        for (uint256 i; i < len; i++) {
            if (chains[user][i] == chainId) {
                chains[user][i] = chains[user][len - 1];
                chains[user].pop();
                isChainInList[user][chainId] = false;
                break;
            }
        }
    }

    function _handleReward(address from, address to) internal {
         if(rewardController != address(0)){
            uint256 fromBalance = balanceBeforeScaledExcludingDeadTokens(from);
            uint256 currentTotalBalance  = totalBalanceBeforeScaledExcludingDeadTokens();
            ICedroRewardController(rewardController).handleReward(from, fromBalance, currentTotalBalance);
            if(from != to){
                uint256 toBalance = balanceBeforeScaledExcludingDeadTokens(to);
                ICedroRewardController(rewardController).handleReward(to, toBalance, currentTotalBalance);
            }
        }
    }

}
