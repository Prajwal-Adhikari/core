// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import './interfaces/ICore.sol';


contract FeeProvider is Initializable,OwnableUpgradeable{
    using SafeMath for uint256;

    mapping(uint16 => mapping(bytes32 => uint)) public OPTIMAL_GLOBAL_LIQUIDITY_FACTOR;
    mapping(uint16 => mapping(bytes32 => uint)) public BASE_FEE;
    mapping(uint16 => mapping(bytes32 => uint)) public MAX_FEE;
    
    address public core;

    function initialize() public initializer {
        __Ownable_init();
        
    }

    /**
    * @dev Sets core contract. 
    * This function can only be accessed by the contract owner.
    * @param _coreAddress address of the pool.
    **/
    function setCore(address _coreAddress) external onlyOwner {
        core = _coreAddress;

    }

    /**
    * @dev Configures Optimal Global Liquidity Factor. 
    * This function can only be accessed by the contract owner.
    * @param _chainId ids of the chain.
    * @param _poolId ids of the pool.
    * @param _liquidityFactor optimal global liquidity factor for each pool in diff chain.
    **/
    function configureOptimalGlobalLiquidityFactor(uint16[] memory _chainId, bytes32[] memory _poolId, uint[] memory _liquidityFactor) external onlyOwner {
        require( _chainId.length == _poolId.length && _poolId.length == _liquidityFactor.length , "Arguments number mismatched");
        for (uint256 i = 0; i < _poolId.length; i++){
            OPTIMAL_GLOBAL_LIQUIDITY_FACTOR[_chainId[i]][_poolId[i]] = _liquidityFactor[i];
        }

    }

    /**
    * @dev Configures Base Global Liquidity Factor. 
    * This function can only be accessed by the contract owner.
    * @param _chainId ids of the chain.
    * @param _poolId ids of the pool.
    * @param _baseFee base fee for each pool in diff chain.
    **/
    function configureBaseFee(uint16[] memory _chainId, bytes32[] memory _poolId, uint[] memory _baseFee) external onlyOwner {
        require( _chainId.length == _poolId.length && _poolId.length == _baseFee.length , "Arguments number mismatched");
        for (uint256 i = 0; i < _poolId.length; i++){
            BASE_FEE[_chainId[i]][_poolId[i]] = _baseFee[i];
        }
 
    }

    /**
    * @dev Configures upper limit of the fee for withdraw. 
    * This function can only be accessed by the contract owner.
    * @param _chainId ids of the chain.
    * @param _poolId ids of the pool.
    * @param _maxFee upper limit of fee for each pool in diff chain.
    
    **/
    function configureMaxFee(uint16[] memory _chainId, bytes32[] memory _poolId, uint[] memory _maxFee) external onlyOwner {
        require( _chainId.length == _poolId.length && _poolId.length == _maxFee.length , "Arguments number mismatched");
        for (uint256 i = 0; i < _poolId.length; i++){
            MAX_FEE[_chainId[i]][_poolId[i]] = _maxFee[i];
        }
 
    }

    /**
    * @dev Returns the amount of fee or reward. 
    * @param _chainId id of the chain.
    * @param _poolId id of the pool.
    **/
    function getFeeAmount(uint16 _chainId, bytes32 _poolId) public view returns (uint){
        // uint globalLiquidityFactor = _getGlobalLiquidityFactor(_chainId, _poolId);
        // uint optimalGlobalLiquidityFactor = OPTIMAL_GLOBAL_LIQUIDITY_FACTOR[_chainId][_poolId];
        // uint initialFee;
        // if (globalLiquidityFactor > 0){
        //     initialFee = BASE_FEE[_chainId][_poolId].add((optimalGlobalLiquidityFactor.sub(globalLiquidityFactor)).mul(optimalGlobalLiquidityFactor).div(globalLiquidityFactor));
        // }
        // if (initialFee < 0) {
        //     initialFee = 0;
        // }
        // uint maxFee = MAX_FEE[_chainId][_poolId];
        return 1e18;
        // return maxFee <= initialFee ? maxFee: initialFee;

    }   

    /**
    * @dev Computes the global liquidity factor of an asset for a chain
    * @param _chainId id of the chain.
    * @param _poolId id of the pool.
    **/
    function _getGlobalLiquidityFactor(uint16 _chainId, bytes32 _poolId) internal view returns (uint){
        uint totalLiquidity = ICore(core).getTotalLiquidity(_poolId);
        return totalLiquidity > 0 ? ICore(core).getLiquidity(_chainId, _poolId).div(totalLiquidity): 0;
    }

}