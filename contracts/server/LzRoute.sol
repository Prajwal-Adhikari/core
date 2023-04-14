// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../layerZero/lzApp/LzApp.sol";
import './interfaces/IAdapter.sol'; 
import "hardhat/console.sol";


/** 
* Title LzRoutePool
* Uses LayerZero functions for sending and receiving messages
**/

contract LzRoutePool is Initializable, LzApp {
    using SafeMath for uint256;

    address public adapter;
    mapping(bytes32 => uint16) public chainID;
    mapping(uint16 => bytes32) public chainName;

    uint8 internal constant TYPE_DEPOSIT = 1;
    uint8 internal constant TYPE_REPAY = 2;

    uint public gasUsage;
    uint constant public BASE = 10 ** 18;


    /**
    * @dev only adapter can use functions affected by this modifier
    **/
    modifier onlyAdapter {
        require(adapter == msg.sender, "The caller must be a pool contract");
        _;
    }


    function initialize(address _lzEndpoint, uint16 _localChainId, uint _gasUsage) public initializer {
        __LzApp_init(_lzEndpoint, _localChainId);
        gasUsage = _gasUsage;
    }


    /**
    * @dev Configures adapter contract. 
    * This function can only be accessed by the contract owner.
    * @param adapterAddress address of the adapter contract.
    **/
    function setAdapter(address adapterAddress) external onlyOwner {
        adapter = adapterAddress;

    }

    /**
    * @dev Links chainId with chain name. 
    * This function can only be accessed by the contract owner.
    * @param chain name of the chain.
    * @param id chain id of the chain.
    **/
    function setChainNameID(bytes32 chain, uint16 id) external onlyOwner {
        chainID[chain] = id;
        chainName[id] = chain;

    }

    /** 
    * @dev Receive a cross chain message sent from the branch of chain with chain id `_srcChainId`.
    * 
    **/
    function _blockingLzReceive(uint16 _srcChainId, bytes memory , uint64 , bytes memory _payload) internal override {
        bytes32 tokenId;
        bytes32 user;
        uint64 amountpx;
        uint64 amountsx;
        uint8 functionType = uint8(_payload[0]);
        assembly {
            tokenId := mload(add(_payload, 33))
            user := mload(add(_payload, 65))
            amountpx := mload(add(_payload, 73))
            amountsx := mload(add(_payload, 81))
        }
        // (, bytes32 tokenId, bytes memory user, uint64 amountpx, uint64 amountsx) = abi.decode(_payload, (uint8, bytes32, bytes, uint64, uint64));
        uint amount = uint(amountpx) * BASE +  uint(amountsx);
        if(functionType == TYPE_DEPOSIT) {  
            IAdapter(adapter).deposit(tokenId, chainName[_srcChainId], _bytesToAddress(user), amount);
        } else if(functionType == TYPE_REPAY) { 
            IAdapter(adapter).repay(tokenId, chainName[_srcChainId], _bytesToAddress(user), amount);
        } 
    }

    /** 
    * @dev sends a cross chain message to chain with chain id `chainId` to send
    * `amount` to `user` from the pool with pool id `id`
    * @param id pool id of pool to release amount from
    * @param chainId chain id of chain to release the amount from
    * @param amount amount to be released
    * @param user deposit address    **/
    function sendToken(bytes32 id, bytes32 chainId, bytes32 user, address sender, uint amount) external payable onlyAdapter {
        bytes memory payload = abi.encodePacked(id, user, uint64(amount / BASE), uint64(amount % BASE));
        require(payload.length == 80, "Bad payload");
        _lzSend(chainID[chainId], payload, payable(sender), address(0x0), "", msg.value);

    }

    /** 
    * @dev Returns the estimated transaction fees to send a cross chain message to
    * the destination chain with chain id `chainId`.
    * @param chainId chain id of the destionation chain.
    **/
    function estimateFees(bytes32 chainId) public view returns (uint) {
        bytes memory payload = abi.encode("", chainID[chainId], msg.sender, 0);
        (uint fees, ) = lzEndpoint.estimateFees(chainID[chainId], address(this), payload, false, abi.encodePacked(uint16(1), gasUsage));
        return fees;
    }

    function _bytesToAddress(bytes32 bys) private pure returns (address addr) {
        return address(uint160(uint256(bys)));
    }
}