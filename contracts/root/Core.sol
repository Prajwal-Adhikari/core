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
 * Title Core
 * Core stores all the global data
 * Most of the lending and borrowing logic like interest rate calculation, checks, etc. is in Core.
 **/
contract Core is Initializable, ContextUpgradeable {
    using SafeMathUpgradeable for uint256;

    IOracle public oracle;
    address public treasury;
    address public roleManager;

    uint256 public constant MAX_HEALTH_FACTOR = 1e18;
    uint256 public constant YEAR = 365 * 86400;

    // key: poolId
    // Example poolId = keccak256("USDC")
    mapping(bytes32 => Data.PoolData) public pools;
    mapping(bytes32 => Data.ConfigData) public configs;
    mapping(bytes32 => uint256) public totalLiquidity; // Stores total liquidity within pool

    // key : [chainId][poolId]
    // chainId = keccak256("FTM")
    // poolId = keccak256("USDC")
    mapping(bytes32 => mapping(bytes32 => uint256)) public chainLiquidity; // Stores liquidity of pool across chain

    mapping(address => bytes32[]) public users; // Stores poolIds of collateral or borrowed assets by a user

    error PoolNotEnabled(uint contractCode, bytes32 id);
    error NotEnoughLiquidity(uint contractCode, bytes32 chainId, bytes32 poolId, uint256 poolLiquidity, uint256 sentAmount);
    error LTVCheckFailed(uint contractCode, bytes32 chainId, bytes32 poolId, uint256 tokenAmount);
    error HealthFactorCheckFailed(uint contractCode, address user);
    error InvalidSender(uint contractCode, address sender);

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

    function initialize(address treasuryAddress, address roleManagerAddress) public initializer {
        treasury = treasuryAddress;
        roleManager = roleManagerAddress;
        
    }

    // Set contract addresses
    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    function setOracle(
        IOracle _oracle
    ) external onlyRole(IRoleManager(roleManager).SET_CORE_METHOD()) {
        oracle = _oracle;
    }

    function initPool(
        bytes32 id,
        Data.ConfigData memory config,
        address _ceToken,
        address _debtToken
    ) external onlyRole(IRoleManager(roleManager).INIT_POOL()) {
        updateInterestRate(id);
        configs[id] = config;
        Data.PoolData storage pool = pools[id];
        pool.ceToken = _ceToken;
        pool.debtToken = _debtToken;
        pool.ceScaled = 1e18;
        pool.dtScaled = 1e18;
    }

    function changePoolStatus(
        bytes32 id,
        bool enable
    ) external onlyRole(IRoleManager(roleManager).POOL_STATUS()) {
        pools[id].enable = enable;
        emit Data.ChangePoolStatus(id, enable);
    }

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
    }

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

        // _;
    }

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

    function deposit(
        bytes32 id,
        bytes32 chainId,
        address user,
        uint256 tokenAmount
    ) external onlyRole(IRoleManager(roleManager).POOL()) returns (uint256) {
        refresh(id);
        Data.PoolData storage pool = pools[id];
        if(! pool.enable)
            revert PoolNotEnabled(9, id);

        uint256 ceAmount = tokenAmount.mul(1e18).div(pool.ceScaled);
        ICEToken(pool.ceToken).mint(user, ceAmount);
        pool.ceSupply = pool.ceSupply.add(ceAmount);
        chainLiquidity[chainId][id] += tokenAmount;
        totalLiquidity[id] += tokenAmount;
        updateInterestRate(id);
        _addToken(user, id);
       
        return ceAmount;
    }

    function withdraw(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount,
        address user,
        bool all
    ) external onlyRole(IRoleManager(roleManager).POOL()) returns (uint256) {
        refresh(id);
        Data.PoolData storage pool = pools[id];
        if(! pool.enable)
            revert PoolNotEnabled(9, id);

        uint256 burnAmount;
        if(all) {
            burnAmount = ICEToken(pool.ceToken).balanceBeforeScaled(user);
            tokenAmount = burnAmount.mul(pool.ceScaled).div(1e18);
        } else {
            burnAmount = tokenAmount.mul(1e18).div(pool.ceScaled);
        } 
        if(chainLiquidity[chainId][id] < tokenAmount)
            revert NotEnoughLiquidity(9, chainId, id, chainLiquidity[chainId][id], tokenAmount);

        ICEToken(pool.ceToken).burn(user, burnAmount);
        _removeToken(user, id);

        pool.ceSupply = pool.ceSupply.sub(burnAmount);
        chainLiquidity[chainId][id] -= tokenAmount;
        totalLiquidity[id] -= tokenAmount;
        updateInterestRate(id);
        checkHealth(user);
        
        return (tokenAmount);
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
        params.price = oracle.getSinglePrice(id).div(1e18);
        params.ltv = config.ltv;
        params.debtToken = pool.debtToken;
    }

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
            revert NotEnoughLiquidity(9, chainId, id, params.liquidity, tokenAmount);

        IDebtToken(params.debtToken).mint(user, params.debtAmount);
        pools[id].debtSupply += params.debtAmount;
        updateInterestRate(id);
        chainLiquidity[chainId][id] -= tokenAmount;
        totalLiquidity[id] -= tokenAmount;

        Data.HealthData memory healthData = healthFactor(user);
        if(
            healthData.collateralValue.mul(params.ltv).div(1e18) <
                healthData.debtValue.add(
                    tokenAmount.mul(params.price).div(1e18))
        )
            revert LTVCheckFailed(9, chainId, id, tokenAmount);

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
                ICEToken(params.ceToken).mint(params.user, ceAmount);
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

    function updateCeAndDebtSupply(
        bytes32 id,
        uint256 ceAmount,
        uint256 debtAmount
    ) external onlyRole(IRoleManager(roleManager).LIQUIDATION_MANAGER()) {
        pools[id].ceSupply = ceAmount;
        pools[id].debtSupply = debtAmount;
    }

    function swap(
        bytes32 id,
        bytes32 srcChainId,
        bytes32 destChainId,
        uint256 tokenAmountInSrc,
        uint256 tokenAmountInDest
    ) external onlyRole(IRoleManager(roleManager).SWAP()) {
        chainLiquidity[srcChainId][id] -= tokenAmountInSrc;
        chainLiquidity[destChainId][id] += tokenAmountInDest;
    }

    function checkHealth(address user) public view {
        if(healthFactor(user).factor >= MAX_HEALTH_FACTOR)
            revert HealthFactorCheckFailed(9, user);
    }

    function handleTransfer(address from, address to, bytes32 id) external {
        if(msg.sender != pools[id].ceToken)
            revert InvalidSender(9, msg.sender);
        checkHealth(from);
        _addToken(to, id);
        _removeToken(from, id);
    }

    function _addToken(address user, bytes32 id) internal {
        for (uint256 i; i < users[user].length; i++) {
            if (users[user][i] == id) {
                return;
            }
        }
        users[user].push(id);
    }

    function addTokenForLiquidator(address user, bytes32 id) external onlyRole(IRoleManager(roleManager).LIQUIDATION_MANAGER()){
        _addToken(user, id);
    }

    function _removeToken(address user, bytes32 id) internal {
        Data.PoolData memory pool = pools[id];
        if(ICEToken(pool.ceToken).balanceOf(user) == 0 && IDebtToken(pool.debtToken).balanceOf(user) == 0) {
            uint length = users[user].length;
            for (uint256 i; i < length; i++) {
                if (users[user][i] == id && i != length - 1) {
                    users[user][i] = users[user][length - 1];
                    break;
                }
            }
            users[user].pop();
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
            .balanceBeforeScaled(_user)
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

    function getCEScaled(bytes32 _poolId) public view returns (uint256)  {
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

    function getDTScaled(bytes32 _poolId) public view returns (uint256) {
        Data.PoolData memory pool = pools[_poolId];
        uint256 increasedDebt = block
            .timestamp
            .sub(pool.lastUpdateTime)
            .mul(pool.borrowInterestRate)
            .div(YEAR);
        return pool.dtScaled.add(increasedDebt);
    }
    
    function getLiquidity(
        bytes32 _chainId,
        bytes32 _poolId
    ) public view returns (uint256) {
        return chainLiquidity[_chainId][_poolId];
    }
}
