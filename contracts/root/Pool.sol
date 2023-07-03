// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/ICEToken.sol";
import "./interfaces/IDebtToken.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ICore.sol";
import "./interfaces/IFeeProvider.sol";
import "./interfaces/IAdapter.sol";
import "./interfaces/IRoleManager.sol";
import "./libraries/Data.sol";
import "../utils/ERC2771ContextUpgradeable.sol";

/**
 * @title Pool
 * @notice Pool is deployed on a single chain
 * @notice All the Branches are connected to Pool, all of which sends deposit and repay information to Pool
 * @notice Users interact with Pool for Borrow, Withdraw, and Liquidate actions
 **/
contract Pool is
    Initializable,
    ReentrancyGuardUpgradeable,
    ERC2771ContextUpgradeable
{
    using SafeMathUpgradeable for uint256;

    // Request Types
    uint8 internal constant TYPE_DEPOSIT = 1;
    uint8 internal constant TYPE_REPAY = 2;
    uint8 internal constant TYPE_SWAP = 3;

    uint256 public constant BASE = 10 ** 18;

    address public feeProvider;
    address public core;
    address public adapter;
    address public roleManager;

    /** 
    * @notice key: [poolId][chainId]
    * @notice poolId = keccak256("USDC")
    * @notice chainId = keccak256("FTM")
    * @notice Pool and chain level pause
    */
    mapping(bytes32 => mapping(bytes32 => bool)) public withdrawPause;
    mapping(bytes32 => mapping(bytes32 => bool)) public borrowPause;

    //Protocol level pause for all pools and chains
    bool public protocolPause;

    bool public feeEnable;

    error ProtocolPaused(uint contractCode);
    error UnsupportedFunctionType(uint contractCode, uint8 functionType);
    error WithdrawPaused(uint contractCode, bytes32 chainId, bytes32 id);
    error BorrowPaused(uint contractCode, bytes32 chainId, bytes32 id);
    error BadPayload(uint contractCode, uint256 currentLength, uint256 requiredLength);

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
     * @param forwarder - The address of forwarder contract.
     * @param roleManagerAddress - The EOA of role manager.
     **/
    function initialize(
        address forwarder,
        address roleManagerAddress
    ) public initializer {
        __ReentrancyGuard_init();
        __ERC2771Context_init(forwarder);
        roleManager = roleManagerAddress;
    }

    /**
     * @notice Configures role manager address
     * This function can only be accessed by account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/    
    function setRoleManager(
        address roleManagerAddress
    ) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    /**
     * @notice Configures fee provider contract.
     * This function can only be accessed by the account with role SET_POOL_METHOD
     * @param feeProviderAddress - address of the fee provider contract.
     **/
    function setFeeProvider(
        address feeProviderAddress
    ) external onlyRole(IRoleManager(roleManager).SET_POOL_METHOD()) {
        feeProvider = feeProviderAddress;
    }

    /**
     * @notice Configures core contract.
     * This function can only be accessed by the account with role SET_POOL_METHOD
     * @param coreAddress - address of the fee provider contract.
     **/
    function setCore(
        address coreAddress
    ) external onlyRole(IRoleManager(roleManager).SET_POOL_METHOD()) {
        core = coreAddress;
    }

    /**
     * @notice Configures adapter contract.
     * This function can only be accessed by the account with role SET_POOL_METHOD
     * @param adapterAddress - address of the adapter contract.
     **/
    function setAdapter(
        address adapterAddress
    ) external onlyRole(IRoleManager(roleManager).SET_POOL_METHOD()) {
        adapter = adapterAddress;
    }

    /**
     * @notice Sets the forwarder address.
     * @param forwarderAddress - Forwarder address.
     **/
    function setForwarder(
        address forwarderAddress
    ) external onlyRole(IRoleManager(roleManager).SET_POOL_METHOD()) {
        _setTrustedForwarder(forwarderAddress);
    }

    /**
     * @notice Configures pool status for withdraw
     * This function can only be accessed by the account with role PROTOCOL_PAUSE
     * @param id - pool id of the asset.
     * @param chainId - id of the chain to withdraw asset from.
     * @param status - status of the pool.
     **/    
    function setWithdrawPause(
        bytes32 id,
        bytes32 chainId,
        bool status
    ) external onlyRole(IRoleManager(roleManager).PROTOCOL_PAUSE()) {
        withdrawPause[id][chainId] = status;
    }

    /**
     * @notice Configures pool status for borrow
     * This function can only be accessed by the account with role PROTOCOL_PAUSE
     * @param id - pool id of the asset.
     * @param chainId - id of the chain to borrow asset from.
     * @param status - status of the pool.
     **/  
    function setBorrowPause(
        bytes32 id,
        bytes32 chainId,
        bool status
    ) external onlyRole(IRoleManager(roleManager).PROTOCOL_PAUSE()) {
        borrowPause[id][chainId] = status;
    }

    /**
     * @notice Toggles the status of the protocol on and off.
     * This function can only be accessed by the account with role PROTOCOL_PAUSE
     **/ 
    function toggleProtocolStatus()
        external
        onlyRole(IRoleManager(roleManager).PROTOCOL_PAUSE())
    {
        protocolPause = !protocolPause;
    }

    /**
     * @notice Configures fee status.
     * This function can only be accessed by the account with role SET_POOL_METHOD
     **/ 
    function toggleFeeEnable()
        external
        onlyRole(IRoleManager(roleManager).SET_POOL_METHOD())
    {
        feeEnable = !feeEnable;
    }

    /**
     * @notice Sends a withdraw request of amount `ceAmount` to address `to` from pool with pool id `id`
     * in chain with chain id `chainId` to core contract
     * This function can be accessed by anyone
     * @param id - pool id of pool to withdraw from
     * @param chainId - chain id of chain to withdraw from
     * @param ceAmount - amount to withdraw
     * @param to - withdraw address
     * @param route - communication protocol
     * @param airdropAmount - amount to be airdropped to destination chain
     **/
    function withdraw(
        bytes32 id,
        bytes32 chainId,
        uint256 ceAmount,
        bytes32 to,
        bytes32 route,
        uint256 airdropAmount,
        bool all
    ) external payable nonReentrant {
  
        if(protocolPause)
            revert ProtocolPaused(13);

        if(withdrawPause[id][chainId])
            revert WithdrawPaused(13, chainId, id);

        uint256 tokenAmount = ICore(core).withdraw(
            id,
            chainId,
            ceAmount,
            _msgSender(),
            all
        );
        if (feeEnable) {
            uint256 fee = IFeeProvider(feeProvider).getFeeAmount(chainId, id);
            tokenAmount -= fee;
        }

        bytes memory payload = abi.encodePacked(
            id,
            to,
            uint64(tokenAmount / BASE),
            uint64(tokenAmount % BASE)
        );
        if(payload.length != 80)
            revert BadPayload(13, payload.length, 80);

        IAdapter(adapter).send{value: msg.value}(
            payload,
            chainId,
            msg.sender,
            airdropAmount,
            _bytesToAddress(to),
            route
        );
        emit Data.Withdraw(
            _msgSender(),
            _bytesToAddress(to),
            id,
            chainId,
            tokenAmount,
            ceAmount,
            route
        );
        emit Data.SendToken(_bytesToAddress(to), id, tokenAmount);
    }

    /**
     * @notice Sends a borrow request of amount `tokenAmount` to address `to` from pool with pool id `id`
     * in chain with chain id `chainId` to core contract
     * This function can be accessed by anyone
     * @param id - pool id of pool to borrow from
     * @param chainId - chain id of chain to borrow from
     * @param tokenAmount - amount to borrow
     * @param to - borrow address
     * @param route - communication protocol
     * @param airdropAmount - amount to be airdropped to destination chain
     **/
    function borrow(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount,
        bytes32 to,
        bytes32 route,
        uint256 airdropAmount
    ) external payable nonReentrant {
        if(protocolPause)
            revert ProtocolPaused(13);

        if(borrowPause[id][chainId])
            revert BorrowPaused(13, chainId, id);

        uint256 debtAmount = ICore(core).borrow(
            id,
            chainId,
            tokenAmount,
            _msgSender()
        );
        if (feeEnable) {
            uint256 fee = IFeeProvider(feeProvider).getFeeAmount(chainId, id);
            tokenAmount -= fee;
        }

        bytes memory payload = abi.encodePacked(
            id,
            to,
            uint64(tokenAmount / BASE),
            uint64(tokenAmount % BASE)
        );
        if(payload.length != 80)
            revert BadPayload(13, payload.length, 80);

        IAdapter(adapter).send{value: msg.value}(
            payload,
            chainId,
            msg.sender,
            airdropAmount,
            _bytesToAddress(to),
            route
        );
        emit Data.Borrow(
            _msgSender(),
            _bytesToAddress(to),
            id,
            chainId,
            tokenAmount,
            debtAmount,
            route
        );
        emit Data.SendToken(_bytesToAddress(to), id, tokenAmount);
    }

    /**
     * @notice Used to repay a borrowed asset.
     * @param id - The pool id.
     * @param chainId - The chainid of the branch contract.
     * @param user - The repayer's address.
     * @param tokenAmount - The repay amount.
     * @param route - The route to use.
     **/
    function _repay(
        bytes32 id,
        bytes32 chainId,
        address user,
        uint256 tokenAmount,
        bytes32 route
    ) internal {
        (uint256 repayAmount, uint256 debtAmount, uint256 ceAmount) = ICore(
            core
        ).repay(id, chainId, user, tokenAmount);
        emit Data.Repay(user, id, chainId, repayAmount, debtAmount, ceAmount, route);
        emit Data.ReceiveToken(user, id, tokenAmount);
    }

    /**
     * @notice Used to deposit asset to the pool.
     * @param id - The pool id.
     * @param chainId - The chainid of the branch contract.
     * @param user - The depositors address.
     * @param tokenAmount - The deposit amount.
     * @param route - The route to use.
     **/
    function _deposit(
        bytes32 id,
        bytes32 chainId,
        address user,
        uint256 tokenAmount,
        bytes32 route
    ) internal {
        uint256 ceAmount = ICore(core).deposit(id, chainId, user, tokenAmount);
        emit Data.Deposit(user, id, chainId, tokenAmount, ceAmount, route);
        emit Data.ReceiveToken(user, id, tokenAmount);
    }

    /**
     * @notice Executes the function according to the request type in the payload
     * This function can only be accessed by the account with role ADAPTER
     * @param _payload - information of pool id, user and token amount
     * @param chainId - chain id of the source chain
     * @param route - communication protocol through which payload is received
     **/
    function execute(
        bytes memory _payload,
        bytes32 chainId,
        bytes32 route
    ) external onlyRole(IRoleManager(roleManager).ADAPTER()) {
        bytes32 tokenId;
        bytes32 data;
        uint64 amountpx;
        uint64 amountsx;
        if(_payload.length != 81)
            revert BadPayload(13, _payload.length, 81);
        
        uint8 functionType = uint8(_payload[0]); // _payload received is encoded in format (uint8, bytes32, bytes32, uint64, uint64)
        assembly {
            tokenId := mload(add(_payload, 33))
            data := mload(add(_payload, 65))
            amountpx := mload(add(_payload, 73))
            amountsx := mload(add(_payload, 81))
        }

        uint256 amount = uint256(amountpx) * BASE + uint256(amountsx);
        if (functionType == TYPE_DEPOSIT) {
            _deposit(tokenId, chainId, _bytesToAddress(data), amount, route);
        } else if (functionType == TYPE_REPAY) {
            _repay(tokenId, chainId, _bytesToAddress(data), amount, route);
        } else {
            revert UnsupportedFunctionType(13, functionType);
        }
    }

    /**
     * @notice Converts bytes32 to address
     * @param bys - The bytes32 data
    **/
    function _bytesToAddress(bytes32 bys) private pure returns (address addr) {
        return address(uint160(uint256(bys)));
    }
}
