// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import '../libraries/Data.sol';


interface ICore {
    function deposit(bytes32 id, uint16 chainId, address user, uint tokenAmount) external returns (uint);
    function withdraw(bytes32 id, uint16 chainId, uint ceAmount, address user) external returns (uint);
    function borrow(bytes32 id, uint16 chainId, uint tokenAmount, address user) external returns (uint);
    function repay(bytes32 id, uint16 chainId, address user, uint tokenAmount) external returns (uint, uint, uint);
    function updateCeAndDebtSupply(bytes32 id, uint ceAmount, uint debtAmount) external;
    function refresh(bytes32 id) external;
    function updateInterestRate(bytes32 id) external;
    function healthFactor(address user) external view returns(Data.HealthData memory health);
    function getLiquidity( uint16 _chainId, bytes32 _poolId) external view returns (uint);
    function totalLiquidity( bytes32 _poolId) external view returns (uint);
    function reserves(bytes32 _poolId) external view returns (Data.ReserveData memory reserve);
    function configs(bytes32 _poolId) external view returns (Data.ConfigData memory config);

    
}