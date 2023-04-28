// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

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
contract Core is Initializable, OwnableUpgradeable {
    using SafeMath for uint256;

    IOracle public oracle;
    address public treasury;
    address public roleManager;

    uint256 public constant MAX_HEALTH_FACTOR = 1e18;
    uint256 public constant YEAR = 365 * 86400;
    mapping(bytes32 => Data.ReserveData) public reserves;
    mapping(bytes32 => Data.ConfigData) public configs;
    mapping(bytes32 => mapping(bytes32 => uint256)) public chains;
    mapping(bytes32 => uint256) public totalLiquidity;
    mapping(address => bytes32[]) public users;

    /**
     * @dev Modifier that checks if caller has a specific role.
     **/
    modifier onlyRole(bytes32 role) {
        IRoleManager(roleManager).checkRole(role, _msgSender());
        _;
    }
    

    function initialize(address _treasury) public initializer {
        treasury = _treasury;
        __Ownable_init();
    }
    

    function setRoleManager(address roleManagerAddress) external onlyOwner {
        roleManager = roleManagerAddress;
    }

    /**
     * @dev Registers a new pool in the protocol.
     * This function can only be accessed by the contract owner.
     * @param id id of the pool to be created
     * @param config a ConfigData struct containing the interest rate and liqudation variables.
     * @param _ceToken address to the ceToken smart contract for this pool.
     * @param _debtToken address to the debtToken smart contract for this pool.
     **/
    function initPool(
        bytes32 id,
        Data.ConfigData memory config,
        address _ceToken,
        address _debtToken
    ) external onlyRole(IRoleManager(roleManager).INIT_POOL()) {
        updateInterestRate(id);
        configs[id] = config;
        Data.ReserveData storage reserve = reserves[id];
        reserve.ceToken = _ceToken;
        reserve.debtToken = _debtToken;
        reserve.ceScaled = 1e18;
        reserve.dtScaled = 1e18;
    }

    /**
     * @dev Freezes/Unfreezes a pool with pool id `id`.
     * This function is only accessible by the contract owner and can be used in extreme cases.
     * @param id id of the pool to freeze/unfreeze
     * @param enable bool to freeze/unfreeze
     **/
    function changePoolStatus(bytes32 id, bool enable) external onlyRole(IRoleManager(roleManager).POOL_STATUS()) {
        reserves[id].enable = enable;
        emit Data.ChangePoolStatus(id, enable);
    }

    function updateInterestRate(bytes32 id) public {
        Data.ReserveData storage reserve = reserves[id];
        Data.ConfigData memory config = configs[id];
        if (reserve.debtSupply > 0) {
            uint256 totalDeposit = reserve.ceSupply.mul(reserve.ceScaled).div(
                1e18
            );
            uint256 totalBorrow = reserve.debtSupply.mul(reserve.dtScaled).div(
                1e18
            );
            uint256 currentRatio = totalBorrow.mul(1e18).div(totalDeposit);

            if (currentRatio <= config.bestRatio) {
                //Rt = R0 + (Ut / Ub) * Rslope1
                reserve.interestRate = config.baseRate.add(
                    currentRatio.mul(config.slope1).div(config.bestRatio)
                );
            } else {
                uint256 one = 1e18;
                //Rt = R0 + Rslope1 + (Ut - Ub) / (1 - Ub) * Rslope2
                reserve.interestRate = config.baseRate.add(config.slope1).add(
                    currentRatio.sub(config.bestRatio).mul(config.slope2).div(
                        one.sub(config.bestRatio)
                    )
                );
            }
            reserve.currentRatio = currentRatio;
        }
    }

    function refresh(bytes32 id) public {
        Data.ReserveData storage reserve = reserves[id];
        if (reserve.ceSupply > 0) {
            uint256 increasedDebt = block
                .timestamp
                .sub(reserve.lastUpdateTime)
                .mul(reserve.interestRate)
                .div(YEAR);
            reserve.dtScaled = reserve.dtScaled.add(increasedDebt);

            uint256 increasedAPY = increasedDebt.mul(reserve.debtSupply).div(1e18);
            uint256 tokenAmountTreasury = increasedAPY
                .mul(configs[id].tsuPercent)
                .div(1e18);
            reserve.ceScaled = reserve.ceScaled.add(
                increasedAPY.sub(tokenAmountTreasury).mul(1e18).div(
                    reserve.ceSupply
                )
            );

            uint256 ceAmountTreasury = tokenAmountTreasury.mul(1e18).div(
                reserve.ceScaled
            );
            ICEToken(reserve.ceToken).mint(treasury, ceAmountTreasury);
            reserve.ceSupply = reserve.ceSupply.add(ceAmountTreasury);
            emit Data.MintToTreasury(id, tokenAmountTreasury, ceAmountTreasury);
        }
        reserve.lastUpdateTime = block.timestamp;

        // _;
    }

    function setOracle(IOracle _oracle) external onlyRole(IRoleManager(roleManager).SET_CORE_METHOD()) {
        oracle = _oracle;
    }

    
    function healthFactor(
        address user
    ) public view returns (Data.HealthData memory health) {
        bytes32[] memory ids = users[user];
        if (ids.length > 0) {
            uint256[] memory prices = oracle.getPrices(ids);
            for (uint256 i = 0; i < ids.length; i++) {
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
        Data.ReserveData storage reserve = reserves[id];
        require(reserve.enable, string.concat(TAG,": Not enable now"));

        uint256 ceAmount = tokenAmount.mul(1e18).div(reserve.ceScaled);
        ICEToken(reserve.ceToken).mint(user, ceAmount);
        reserve.ceSupply = reserve.ceSupply.add(ceAmount);
        chains[chainId][id] += tokenAmount;
        totalLiquidity[id] += tokenAmount;
        updateInterestRate(id);
        addToken(user, id);
        emit Data.ReceiveToken(user, id, tokenAmount);

        return ceAmount;
    }

 
    function withdraw(
        bytes32 id,
        bytes32 chainId,
        uint256 ceAmount,
        address user
    ) external onlyRole(IRoleManager(roleManager).POOL()) returns (uint256) {
        refresh(id);
        Data.ReserveData storage reserve = reserves[id];
        require(reserve.enable, string.concat(TAG,": Not enable now"));

        uint256 tokenAmount = reserve.ceScaled.mul(ceAmount).div(1e18);
        require(chains[chainId][id] >= tokenAmount, string.concat(TAG,": No enough liquidity"));
        ICEToken(reserve.ceToken).burn(user, ceAmount);
        reserve.ceSupply = reserve.ceSupply.sub(ceAmount);
        chains[chainId][id] -= tokenAmount;
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
        Data.ReserveData memory reserve = reserves[id];
        Data.ConfigData memory config = configs[id];
        params.liquidity = chains[chainId][id];
        params.debtAmount = tokenAmount.mul(1e18).div(reserve.dtScaled);
        params.price = oracle.getSinglePrice(id).div(1e18);
        params.ltv = config.ltv;
        params.debtToken = reserve.debtToken;
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
        addToken(user, id);

        require(params.liquidity >= tokenAmount, string.concat(TAG,": No enough liquidity"));
        IDebtToken(params.debtToken).mint(user, params.debtAmount);
        reserves[id].debtSupply += params.debtAmount;
        updateInterestRate(id);
        chains[chainId][id] -= tokenAmount;
        totalLiquidity[id] -= tokenAmount;

        Data.HealthData memory healthData = healthFactor(user);
        require(
            healthData.collateralValue.mul(params.ltv).div(1e18) >=
                healthData.debtValue.add(
                    tokenAmount.mul(params.price).div(1e18)
                ),
            "LTV check failed"
        );
        return params.debtAmount;
    }

    // calculate repay info and avoid stack too deep error
    function _buildRepayParams(
        Data.ReserveData memory reserve,
        address user,
        uint256 tokenAmount
    ) internal view returns (Data.RepayParams memory params) {
        params.ceToken = reserve.ceToken;
        params.debtToken = reserve.debtToken;
        params.dtScaled = reserve.dtScaled;
        params.ceScaled = reserve.ceScaled;
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
    ) external onlyRole(IRoleManager(roleManager).POOL()) returns (uint256, uint256, uint256) {
        refresh(id);
        Data.RepayParams memory params = _buildRepayParams(
            reserves[id],
            user,
            tokenAmount
        );
        Data.ReserveData storage reserve = reserves[id];
        uint256 ceAmount = 0;
        if (params.tokenAmount >= params.repayAmount) {
            ceAmount = params.tokenAmount.sub(params.repayAmount).mul(1e18).div(
                params.ceScaled
            );
            if (ceAmount > 0) {
                ICEToken(params.ceToken).mint(params.user, ceAmount);
                reserve.ceSupply = reserve.ceSupply.add(ceAmount);
            }
        } else {
            params.repayAmount = params.tokenAmount;
            params.debtAmount = params.repayAmount.mul(1e18).div(
                params.dtScaled
            );
        }
        chains[chainId][id] += tokenAmount;
        totalLiquidity[id] += tokenAmount;
        IDebtToken(params.debtToken).burn(params.user, params.debtAmount);
        reserve.debtSupply -= params.debtAmount;
        updateInterestRate(id);
        emit Data.ReceiveToken(user, id, tokenAmount);
        return (params.repayAmount, params.debtAmount, ceAmount);
    }

    function updateCeAndDebtSupply(
        bytes32 id,
        uint256 ceAmount,
        uint256 debtAmount
    ) external onlyRole(IRoleManager(roleManager).LIQUIDATION_MANAGER()) {
        reserves[id].ceSupply = ceAmount;
        reserves[id].debtSupply = debtAmount;
    }

     function swap(bytes32 id, bytes32 srcChainId, bytes32 destChainId, uint256 tokenAmount) external onlyRole(IRoleManager(roleManager).POOL()) {
        chains[srcChainId][id] -= tokenAmount;
        chains[destChainId][id] += tokenAmount;
    }

    function checkHealth(address user) public view {
        require(healthFactor(user).factor < MAX_HEALTH_FACTOR, string.concat(TAG,": Health failed"));
    }

    function addToken(address user, bytes32 id) internal {
        for (uint256 i = 0; i < users[user].length; i++) {
            if (users[user][i] == id) {
                return;
            }
        }
        users[user].push(id);
    }

    function _getValues(
        address user,
        uint256 price,
        bytes32 id
    ) internal view returns (uint256 collateralValue, uint256 debtValue) {
        Data.ReserveData memory reserve = reserves[id];
        address _user = user;

        uint256 increasedDebt = block
            .timestamp
            .sub(reserve.lastUpdateTime)
            .mul(reserve.interestRate)
            .div(YEAR);
        uint256 dtScaled = reserve.dtScaled.add(increasedDebt);
        uint256 ceScaled = reserve.ceScaled.add(
            increasedDebt
                .mul(reserve.currentRatio)
                .div(1e18)
                .mul(1e18 - configs[id].tsuPercent)
                .div(1e18)
        );
        collateralValue = ICEToken(reserve.ceToken)
            .balanceBeforeScaled(_user)
            .mul(ceScaled)
            .div(1e18)
            .mul(price)
            .div(1e18);
        debtValue = IDebtToken(reserve.debtToken)
            .balanceBeforeScaled(_user)
            .mul(dtScaled)
            .div(1e18)
            .mul(price)
            .div(1e18);
    }

    function getCEScaled(bytes32 _poolId) public view returns (uint256)  {
        Data.ReserveData memory reserve = reserves[_poolId];
        uint256 increasedDebt = block
            .timestamp
            .sub(reserve.lastUpdateTime)
            .mul(reserve.interestRate)
            .div(YEAR);
        return reserve.dtScaled.add(increasedDebt);
    }

    function getDTScaled(bytes32 _poolId) public view returns (uint256) {
        Data.ReserveData memory reserve = reserves[_poolId];
        uint256 increasedDebt = block
            .timestamp
            .sub(reserve.lastUpdateTime)
            .mul(reserve.interestRate)
            .div(YEAR);
        return reserve.ceScaled.add(
            increasedDebt
                .mul(reserve.currentRatio)
                .div(1e18)
                .mul(1e18 - configs[_poolId].tsuPercent)
                .div(1e18)
        );
    }
    
    function getLiquidity(
        bytes32 _chainId,
        bytes32 _poolId
    ) public view returns (uint256) {
        return chains[_chainId][_poolId];
    }
}
