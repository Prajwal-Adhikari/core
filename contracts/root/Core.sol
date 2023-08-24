// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "./interfaces/ICEToken.sol";
import "./interfaces/IDebtToken.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IRoleManager.sol";
import "./libraries/Data.sol";

string constant TAG = "Core";

/**
 * @title Core
 * @notice Core stores all the global data
 * @notice Most of the lending and borrowing logic like interest rate calculation, checks, is in Core.
 **/
contract Core is Initializable, ContextUpgradeable {
    using SafeMathUpgradeable for uint256;

    IOracle public oracle;
    address public treasury;
    address public roleManager;

    uint256 public constant MAX_HEALTH_FACTOR = 1e18;
    uint256 public constant YEAR = 365 * 86400;

    /** @notice key: poolId
    * @notice example poolId = keccak256("USDC")
    */
    mapping(bytes32 => Data.PoolData) public pools;
    mapping(bytes32 => Data.ConfigData) public configs;
    mapping(bytes32 => uint256) public totalLiquidity; // Stores total liquidity within pool

    /** @notice key : [chainId][poolId]
    * @notice chainId = keccak256("FTM")
    * @notice poolId = keccak256("USDC")
    */
    mapping(bytes32 => mapping(bytes32 => uint256)) public chainLiquidity; // Stores liquidity of pool across chain

    mapping(address => bytes32[]) public users; // Stores poolIds of collateral or borrowed assets by a user
    mapping(address => mapping(bytes32 => bool)) isPoolInList;

    error PoolNotEnabled(string contractTAG, bytes32 id);
    error NotEnoughLiquidity(string contractTAG, bytes32 chainId, bytes32 poolId, uint256 poolLiquidity, uint256 sentAmount);
    error LTVCheckFailed(string contractTAG, bytes32 poolId, uint256 tokenAmount, uint256 collateralValue, uint256 debtValue);
    error HealthFactorCheckFailed(string contractTAG, address user);
    error InvalidSender(string contractTAG, address sender);
    error ChainNotDead(string contractTAG, bytes32 chainId);
    error ExcessLiquidityInDest(string contractTAG);
    error HighDiscountPercentage(string contractTAG);

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
     * @param treasuryAddress - The address of treasury contract.
     * @param roleManagerAddress - The EOA of role manager.
     **/
    function initialize(address treasuryAddress, address roleManagerAddress) public initializer {
        treasury = treasuryAddress;
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
     * @notice Sets the oracle address.
     * This function can only be accessed by the account with role SET_CORE_METHOD.
     * @param _oracle - Oracle address.
     **/
    function setOracle(
        IOracle _oracle
    ) external onlyRole(IRoleManager(roleManager).SET_CORE_METHOD()) {
        oracle = _oracle;
    }

    /**
     * @notice Registers a new pool in the protocol.
     * This function can only be accessed by account with role INIT_POOL.
     * @param id - id of the pool to be created
     * @param config - a ConfigData struct containing the interest rate and liqudation variables.
     * @param _ceToken - address to the ceToken smart contract for this pool.
     * @param _debtToken - address to the debtToken smart contract for this pool.
     **/
    function initPool(
        bytes32 id,
        Data.ConfigData memory config,
        address _ceToken,
        address _debtToken
    ) external onlyRole(IRoleManager(roleManager).INIT_POOL()) {
        if (config.liqMaxDiscount > 2e17)
            revert HighDiscountPercentage(TAG);

        updateInterestRate(id);
        configs[id] = config;
        Data.PoolData storage pool = pools[id];
        pool.ceToken = _ceToken;
        pool.debtToken = _debtToken;
        pool.ceScaled = 1e18;
        pool.dtScaled = 1e18;
    }

    /**
     * @notice Freezes/Unfreezes a pool with pool id `id`.
     * This function can only be accessed by account with role POOL_STATUS.
     * @param id - id of the pool to freeze/unfreeze
     * @param enable - bool to freeze/unfreeze
     **/
    function changePoolStatus(
        bytes32 id,
        bool enable
    ) external onlyRole(IRoleManager(roleManager).POOL_STATUS()) {
        pools[id].enable = enable;
        emit Data.ChangePoolStatus(id, enable);
    }

    /**
     * @notice Updates the interest rate and utilization ratio of the pool.
     * This function is public.
     * @param id - pool id
     **/
    function updateInterestRate(bytes32 id) public {
        Data.PoolData storage pool = pools[id];
        Data.ConfigData memory config = configs[id];
        if (pool.debtSupply > 0) {
            uint256 totalDeposit = pool.ceSupply.mul(pool.ceScaled).div(1e18); // Total deposit amount in real time
            uint256 totalBorrow = pool.debtSupply.mul(pool.dtScaled).div(1e18); // Total borrow amount in real time
            uint256 utilizationRatio = totalBorrow.mul(1e18).div(totalDeposit); // Utilization ratio = Borrow/Deposit

            if (utilizationRatio <= config.optimalUtilizationRatio) {
                //Rt = R0 + (Ut / Ub) * Rslope1
                pool.borrowInterestRate = config.baseRate.add(
                    utilizationRatio.mul(config.slope1).div(
                        config.optimalUtilizationRatio
                    )
                );
            } else {
                uint256 one = 1e18;
                //Rt = R0 + Rslope1 + (Ut - Ub) / (1 - Ub) * Rslope2
                pool.borrowInterestRate = config.baseRate.add(config.slope1).add(
                    utilizationRatio
                        .sub(config.optimalUtilizationRatio)
                        .mul(config.slope2)
                        .div(one.sub(config.optimalUtilizationRatio))
                );
            }
            pool.utilizationRatio = utilizationRatio;
        }

        emit Data.InterestRateUpdated(pool.borrowInterestRate,pool.utilizationRatio);
    }

    /**
     * @notice Refreshes the parameters of the pool.
     * This function is public.
     * @param id - pool id
     **/
    function refresh(bytes32 id) public {
        Data.PoolData storage pool = pools[id];
        if (pool.ceSupply > 0) {
            // Calculating increased Debt factor from previous transaction till now
            uint256 increasedDebtFactor = block
                .timestamp
                .sub(pool.lastUpdateTime)
                .mul(pool.borrowInterestRate)
                .div(YEAR);
            pool.dtScaled = pool.dtScaled.add(increasedDebtFactor);

            uint256 increasedDebtAmount = increasedDebtFactor.mul(pool.debtSupply).div(1e18);
            
            uint256 tokenAmountTreasury = increasedDebtAmount
                .mul(configs[id].treasuryPercent)
                .div(1e18);
            pool.ceScaled = pool.ceScaled.add(
                increasedDebtAmount.sub(tokenAmountTreasury).mul(1e18).div(
                    pool.ceSupply
                )
            );

            uint256 ceAmountTreasury = tokenAmountTreasury.mul(1e18).div(
                pool.ceScaled
            );
            ICEToken(pool.ceToken).mint(treasury, ceAmountTreasury);
            pool.ceSupply = pool.ceSupply.add(ceAmountTreasury);
            emit Data.MintToTreasury(id, tokenAmountTreasury, ceAmountTreasury);
        }
        pool.lastUpdateTime = block.timestamp;
    }

    /**
     * @notice Returns the health factor of the address `user`.
     * @param user - wallet address for which the health factor is calculated.
     **/
    function healthFactor(
        address user
    ) public view returns (Data.HealthData memory health) {
        bytes32[] memory ids = users[user];
        if (ids.length > 0) {
            uint256[] memory prices = oracle.getPrices(ids);
            for (uint256 i; i < ids.length; i++) {
                (uint256 collateralValue, uint256 debtValue) = _getValues(
                    user,
                    prices[i],
                    ids[i]
                );
                health.collateralValue = health.collateralValue.add(
                    collateralValue
                );
                health.debtValue = health.debtValue.add(debtValue);
                health.ltsValue = health.ltsValue.add(
                    collateralValue.mul(configs[ids[i]].liqThreshold).div(1e18)
                );
            }

            if (health.ltsValue > 0) {
                health.factor = health.debtValue.mul(1e18).div(health.ltsValue);
            } else if(health.debtValue > 0) {
                health.factor = MAX_HEALTH_FACTOR;
            }
        } 
    }  

    /**
     * @notice Updates the global protocol states after receiving deposit information
     * of amount `tokenAmount` from address `user` for pool with pool id 'id' from
     * chain with chain id `chainId`.
     * This function can only be accessed by account with role POOL.
     * @param id - pool id of pool where amount was deposited to
     * @param chainId -  chain id of chain deposited to
     * @param user - deposit address
     * @param tokenAmount - amount deposited
     **/
    function deposit(
        bytes32 id,
        bytes32 chainId,
        address user,
        uint256 tokenAmount
    ) external onlyRole(IRoleManager(roleManager).POOL()) returns (uint256) {
        refresh(id);
        Data.PoolData storage pool = pools[id];
        if(! pool.enable)
            revert PoolNotEnabled(TAG, id);

        uint256 ceAmount = tokenAmount.mul(1e18).div(pool.ceScaled);
        ICEToken(pool.ceToken).mintInChain(user, ceAmount, chainId);
        pool.ceSupply = pool.ceSupply.add(ceAmount);
        chainLiquidity[chainId][id] += tokenAmount;
        totalLiquidity[id] += tokenAmount;
        updateInterestRate(id);
        _addToken(user, id);
       
        return ceAmount;
    }

    /**
     * @notice Sends a withdraw request of amount `ceAmount` to address `user` from pool with pool id `id`
     * in chain with chain id `chainId`.
     * This function can only be accessed by account with role POOL.
     * @param id - pool id of pool to withdraw from
     * @param chainId - chain id of chain to withdraw from
     * @param tokenAmount - amount to withdraw
     * @param user - withdraw address
     **/
    function withdraw(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount,
        address user
    ) external onlyRole(IRoleManager(roleManager).POOL()) returns (uint256) {
        refresh(id);
        Data.PoolData storage pool = pools[id];
        if(! pool.enable)
            revert PoolNotEnabled(TAG, id);

        uint256 burnAmount = tokenAmount.mul(1e18).div(pool.ceScaled);
         
        if(chainLiquidity[chainId][id] < tokenAmount)
            revert NotEnoughLiquidity(TAG, chainId, id, chainLiquidity[chainId][id], tokenAmount);

        uint256 balanceInChainId = ICEToken(pool.ceToken).balancePerChain(user, chainId);
        if (balanceInChainId >= burnAmount) {
            ICEToken(pool.ceToken).burnFromChain(user, burnAmount, chainId);
        } else {
            ICEToken(pool.ceToken).burnFromChain(user, balanceInChainId, chainId);
            ICEToken(pool.ceToken).burn(user, burnAmount - balanceInChainId);

        }
        _removeToken(user, id);

        pool.ceSupply = pool.ceSupply.sub(burnAmount);
        chainLiquidity[chainId][id] -= tokenAmount;
        totalLiquidity[id] -= tokenAmount;
        updateInterestRate(id);
        checkHealth(user);
        
        return (burnAmount);
    }

    function withdrawDeadTokens(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount,
        address user,
        bool all
    ) external onlyRole(IRoleManager(roleManager).POOL()) returns (uint256) {
        refresh(id);
        Data.PoolData storage pool = pools[id];
        // require(pool.enable, string.concat(TAG, ": Not enable now"));

        if (! ICEToken(pool.ceToken).isChainDead(chainId))
            revert ChainNotDead(TAG, chainId); 

        if(! pool.enable)
            revert PoolNotEnabled(TAG, id);

        uint256 burnAmount;
        uint256 balanceInChainId = ICEToken(pool.ceToken).balancePerChain(user, chainId);
        if(all) {
            burnAmount = balanceInChainId;
            tokenAmount = burnAmount.mul(pool.ceScaled).div(1e18);
        } else {
            burnAmount = tokenAmount.mul(1e18).div(pool.ceScaled); 
            if( balanceInChainId < burnAmount)
            revert NotEnoughLiquidity(TAG, chainId, id, balanceInChainId, burnAmount);
        }
        if(chainLiquidity[chainId][id] < tokenAmount)
            revert NotEnoughLiquidity(TAG, chainId, id, chainLiquidity[chainId][id], tokenAmount);

        ICEToken(pool.ceToken).burnFromChain(user, burnAmount, chainId);

        _removeToken(user, id);

        pool.ceSupply = pool.ceSupply.sub(burnAmount);
        chainLiquidity[chainId][id] -= tokenAmount;
        totalLiquidity[id] -= tokenAmount;
        updateInterestRate(id);
        checkHealth(user);
        
        return (burnAmount);
    }

    // avoid stack too deep error
    function _buildBorrowParams(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount
    ) internal view returns (Data.BorrowParams memory params) {
        Data.PoolData memory pool = pools[id];
        Data.ConfigData memory config = configs[id];
        params.liquidity = chainLiquidity[chainId][id];
        params.debtAmount = tokenAmount.mul(1e18).div(pool.dtScaled);
        
        params.price = oracle.getSinglePrice(id);
        params.ltv = config.ltv;
        params.debtToken = pool.debtToken;
    }

    /**
     * @notice Sends a borrow request of amount `tokenAmount` to address `user` from pool with pool id `id`
     * in chain with chain id `chainId`.
     * This function can only be accessed by account with role POOL.
     * @param id - pool id of pool to borrow from
     * @param chainId - chain id of chain to borrow from
     * @param tokenAmount - amount to borrow
     * @param user - borrow address
     **/
    function borrow(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount,
        address user
    ) external onlyRole(IRoleManager(roleManager).POOL()) returns (uint256) {
        refresh(id);
        Data.BorrowParams memory params = _buildBorrowParams(
            id,
            chainId,
            tokenAmount
        );
        _addToken(user, id);

        if(params.liquidity < tokenAmount)
            revert NotEnoughLiquidity(TAG, chainId, id, params.liquidity, tokenAmount);

        IDebtToken(params.debtToken).mint(user, params.debtAmount);
        pools[id].debtSupply += params.debtAmount;
        updateInterestRate(id);
        chainLiquidity[chainId][id] -= tokenAmount;
        totalLiquidity[id] -= tokenAmount;

        Data.HealthData memory healthData = healthFactor(user);

        uint256 collateral = healthData.collateralValue.mul(params.ltv).div(1e18);
        uint256 debt =  healthData.debtValue;
        if( collateral < debt)
            revert LTVCheckFailed(TAG, id, tokenAmount, collateral, debt);

        return params.debtAmount;
    }

    // calculate repay info and avoid stack too deep error
    function _buildRepayParams(
        Data.PoolData memory pool,
        address user,
        uint256 tokenAmount
    ) internal view returns (Data.RepayParams memory params) {
        params.ceToken = pool.ceToken;
        params.debtToken = pool.debtToken;
        params.dtScaled = pool.dtScaled;
        params.ceScaled = pool.ceScaled;
        params.debtAmount = IDebtToken(params.debtToken).balanceBeforeScaled(user);
        params.repayAmount = params.debtAmount.mul(params.dtScaled).div(1e18);
        params.tokenAmount = tokenAmount;
        params.user = user;
    }

    /**
     * @notice Updates the global protocol states after receiving repay information
     * of amount `tokenAmount` from address `user` for pool with pool id 'id' from
     * chain with chain id `chainId`.
     * @param id - pool id of pool where amount was repaid to
     * @param chainId - chain id of chain repaid from
     * @param user - repay address
     * @param tokenAmount - amount repaid
     **/
    function repay(
        bytes32 id,
        bytes32 chainId,
        address user,
        uint256 tokenAmount
    )
        external
        onlyRole(IRoleManager(roleManager).POOL())
        returns (uint256, uint256, uint256)
    {
        refresh(id);
        Data.RepayParams memory params = _buildRepayParams(
            pools[id],
            user,
            tokenAmount
        );
        Data.PoolData storage pool = pools[id];
        uint256 ceAmount = 0;
        if (params.tokenAmount >= params.repayAmount) {
            ceAmount = params.tokenAmount.sub(params.repayAmount).mul(1e18).div(
                params.ceScaled
            );
            if (ceAmount > 0) {
                ICEToken(params.ceToken).mintInChain(params.user, ceAmount, chainId);
                pool.ceSupply = pool.ceSupply.add(ceAmount);
            }
        } else {
            params.repayAmount = params.tokenAmount;
            params.debtAmount = params.repayAmount.mul(1e18).div(
                params.dtScaled
            );
        }
      
        chainLiquidity[chainId][id] += tokenAmount;
        totalLiquidity[id] += tokenAmount;
        IDebtToken(params.debtToken).burn(params.user, params.debtAmount);
        _removeToken(user, id);
        pool.debtSupply -= params.debtAmount;
        updateInterestRate(id);

        return (params.repayAmount, params.debtAmount, ceAmount);
    }

    /**
     * @notice Updates ceSupply and debtSupply of the pool
     * This function can only be accessed by account with role LIQUIDATION_MANAGER.
     * @param id - id of the pool
     * @param ceAmount - amount of ceSupply
     * @param debtAmount - amount of debtSupply
     **/
    function updateCeAndDebtSupply(
        bytes32 id,
        uint256 ceAmount,
        uint256 debtAmount
    ) external onlyRole(IRoleManager(roleManager).LIQUIDATION_MANAGER()) {
        pools[id].ceSupply = ceAmount;
        pools[id].debtSupply = debtAmount;
    }

    /**
     * @notice Swaps liquidity amount from one chain to another
     * This function can only be accessed by account with role POOL.
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
    ) external onlyRole(IRoleManager(roleManager).POOL()) {
        if (tokenAmountInDest > tokenAmountInSrc) {
            revert ExcessLiquidityInDest(TAG);
        }
        chainLiquidity[srcChainId][id] -= tokenAmountInSrc;
        chainLiquidity[destChainId][id] += tokenAmountInDest;
        totalLiquidity[id] -= tokenAmountInSrc.sub(tokenAmountInDest);
    }

    /**
     * @notice Check the health factor for a users borrow.
     * @param user - The user's address .
     **/
    function checkHealth(address user) public view {
        if(healthFactor(user).factor >= MAX_HEALTH_FACTOR)
            revert HealthFactorCheckFailed(TAG, user);
    }

    /**
     * @notice Reverts if the health factor is not less than MAX_HEALTH_FACTOR, then add the pool to user as collateral
     * @param from - wallet address the user send ceToken.
     * @param to - wallet address the user receive ceToken.
     * * @param to - pool id.
     **/
    function handleTransfer(address from, address to, bytes32 id) external {
        if(msg.sender != pools[id].ceToken)
            revert InvalidSender(TAG, msg.sender);
        checkHealth(from);
        _addToken(to, id);
        _removeToken(from, id);
    }

    function _addToken(address user, bytes32 id) internal {
        if(isPoolInList[user][id])
            return;
        isPoolInList[user][id] = true;
        users[user].push(id);
    }

    /**
     * @notice Adds pool id to liquidator's token list
     * This function can only be accessed by account with role LIQUIDATION_MANAGER.
     * @param user - address of the liquidator
     * @param id - pool id of the asset.
     **/
    function addTokenForLiquidator(address user, bytes32 id) external onlyRole(IRoleManager(roleManager).LIQUIDATION_MANAGER()){
        _addToken(user, id);
    }

    /**
     * @notice Returns list of the tokens the `user` has 
     * @param user - address of the user
     **/
    function getTokens(
       address user
    ) public view returns (bytes32[] memory){
        return users[user];
    }

    function _removeToken(address user, bytes32 id) internal {
        Data.PoolData memory pool = pools[id];
        if(ICEToken(pool.ceToken).balanceOf(user) == 0 && IDebtToken(pool.debtToken).balanceOf(user) == 0) {
            uint256 len = users[user].length;
            for (uint256 i; i < len; i++) {
                if (users[user][i] == id) {
                    users[user][i] = users[user][len -1];
                    users[user].pop();
                    isPoolInList[user][id] = false;
                    break;
                }
            }
           
        }
    }

    function _getValues(
        address user,
        uint256 price,
        bytes32 id
    ) internal view returns (uint256 collateralValue, uint256 debtValue) {
        Data.PoolData memory pool = pools[id];
        address _user = user;

        uint256 increasedDebtFactor = block
            .timestamp
            .sub(pool.lastUpdateTime)
            .mul(pool.borrowInterestRate)
            .div(YEAR);
        uint256 dtScaled = pool.dtScaled.add(increasedDebtFactor);
        uint256 ceScaled = pool.ceScaled.add(
            increasedDebtFactor
                .mul(pool.utilizationRatio)
                .div(1e18)
                .mul(1e18 - configs[id].treasuryPercent)
                .div(1e18)
        );

        collateralValue = ICEToken(pool.ceToken)
            .balanceBeforeScaledExcludingDeadTokens(_user)
            .mul(ceScaled)
            .div(1e18)
            .mul(price)
            .div(1e18);

        debtValue = IDebtToken(pool.debtToken)
            .balanceBeforeScaled(_user)
            .mul(dtScaled)
            .div(1e18)
            .mul(price)
            .div(1e18);
    }

    /**
     * @notice Get the CE scaled amount.
     * @param _poolId - The pool id .
     **/
    function getCEScaled(bytes32 _poolId) external view returns (uint256)  {
        Data.PoolData memory pool = pools[_poolId];
        uint256 increasedDebt = block
            .timestamp
            .sub(pool.lastUpdateTime)
            .mul(pool.borrowInterestRate)
            .div(YEAR);
        return pool.ceScaled.add(
            increasedDebt
                .mul(pool.utilizationRatio)
                .div(1e18)
                .mul(1e18 - configs[_poolId].treasuryPercent)
                .div(1e18)
        );
    }

    /**
     * @notice Get the DT scaled amount.
     * @param _poolId - The pool id .
     **/
    function getDTScaled(bytes32 _poolId) external view returns (uint256) {
        Data.PoolData memory pool = pools[_poolId];
        uint256 increasedDebt = block
            .timestamp
            .sub(pool.lastUpdateTime)
            .mul(pool.borrowInterestRate)
            .div(YEAR);
        return pool.dtScaled.add(increasedDebt);
    }
    
    /**
     * @notice Returns liquidity of an asset for a chain
     * @param _chainId - id of the chain.
     * @param _poolId - id of the pool.
     **/
    function getLiquidity(
        bytes32 _chainId,
        bytes32 _poolId
    ) external view returns (uint256) {
        return chainLiquidity[_chainId][_poolId];
    }

    /**
     * @notice Returns total withdrawable balance of an asset for a user
     * @param _poolId - id of the pool.
     * @param _user - address of the user
     **/
    function getWithdrawableBalancePerPool(
        bytes32 _poolId,
        address _user
    ) external view returns (uint256) {
        Data.PoolData storage pool = pools[_poolId];
        return  ICEToken(pool.ceToken).balanceOfExcludingDeadTokens(_user);
    
        
    }
}
