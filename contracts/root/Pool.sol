// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "hardhat/console.sol";
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
import "./libraries/Data.sol";
import "../utils/ERC2771ContextUpgradeable.sol";

string constant TAG = "Pool";

/**
 * Title Pool
 * Pool is deployed on a single chain
 * All the Branches are connected to Pool, all of which sends deposit and repay information
 * to Pool
 * Users interact with Pool for Borrow, Withdraw, and Liquidate actions
 **/
contract Pool is Initializable, ReentrancyGuardUpgradeable, ERC2771ContextUpgradeable {
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

    // key: [poolId][chainId]
    // poolId = keccak256("USDC")
    // chainId = keccak256("FTM")
    // Pool and chain level pause
    mapping(bytes32 => mapping(bytes32 => bool)) public withdrawPause;
    mapping(bytes32 => mapping(bytes32 => bool)) public borrowPause;

    // Protocol level pause for all pools and chains
    bool public protocolPause;

    bool public feeEnable;

    function initialize(address forwarder, address roleManagerAddress) public initializer {
        __ReentrancyGuard_init();
        __ERC2771Context_init(forwarder);
        roleManager = roleManagerAddress;
    }

    /**
     * @dev Modifier that checks if caller has a specific role.
     **/
    modifier onlyRole(bytes32 role) {
        IRoleManager(roleManager).checkRole(role, _msgSender());
        _;
    }

    // Set contract addresses
    function setRoleManager(address roleManagerAddress) external  {
        roleManager = roleManagerAddress;
    }

    function setFeeProvider(
        address feeProviderAddress
    ) external onlyRole(IRoleManager(roleManager).SET_POOL_METHOD()) {
        feeProvider = feeProviderAddress;
    }

    function setCore(
        address coreAddress
    ) external onlyRole(IRoleManager(roleManager).SET_POOL_METHOD()) {
        core = coreAddress;
    }

    function setAdapter(
        address adapterAddress
    ) external onlyRole(IRoleManager(roleManager).SET_POOL_METHOD()) {
        adapter = adapterAddress;
    }

    function setForwarder(
        address forwarderAddress
    ) external onlyRole(IRoleManager(roleManager).SET_POOL_METHOD()) {
        _setTrustedForwarder(forwarderAddress);
    }

    // Pausing methods
    function setWithdrawPause(
        bytes32 id,
        bytes32 chainId,
        bool status
    ) external onlyRole(IRoleManager(roleManager).PROTOCOL_PAUSE()) {
        withdrawPause[id][chainId] = status;
    }

    function setBorrowPause(
        bytes32 id,
        bytes32 chainId,
        bool status
    ) external onlyRole(IRoleManager(roleManager).PROTOCOL_PAUSE()) {
        borrowPause[id][chainId] = status;
    }

    function toggleProtocolStatus()
        external
        onlyRole(IRoleManager(roleManager).PROTOCOL_PAUSE())
    {
        protocolPause = !protocolPause;
    }

    // Enable fee for borrow and withdraw tx
    function toggleFeeEnable()
        external
        onlyRole(IRoleManager(roleManager).SET_POOL_METHOD())
    {
        feeEnable = !feeEnable;
    }

    function withdraw(
        bytes32 id,
        bytes32 chainId,
        uint256 ceAmount,
        bytes32 to,
        bytes32 route,
        uint256 airdropAmount
    ) external payable nonReentrant {
        require(
            !(withdrawPause[id][chainId] || protocolPause),
            string.concat(TAG, ": Withdraw paused")
        );
        uint256 tokenAmount = ICore(core).withdraw(
            id,
            chainId,
            ceAmount,
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
        require(payload.length == 80, string.concat(TAG, "Bad payload"));
        IAdapter(adapter).send{value: msg.value}(
            payload,
            chainId,
            msg.sender,
            airdropAmount,
            route
        );
        emit Data.Withdraw(
            _msgSender(),
            _bytesToAddress(to),
            id,
            chainId,
            tokenAmount,
            ceAmount
        );
        emit Data.SendToken(_msgSender(), id, tokenAmount);
    }

    function borrow(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount,
        bytes32 to,
        bytes32 route,
        uint256 airdropAmount
    ) external payable nonReentrant {
        require(
            !(borrowPause[id][chainId] || protocolPause),
            string.concat(TAG, ": Borrow paused")
        );
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
        IAdapter(adapter).send{value: msg.value}(
            payload,
            chainId,
            msg.sender,
            airdropAmount,
            route
        );
        emit Data.Borrow(
            _msgSender(),
            _bytesToAddress(to),
            id,
            chainId,
            tokenAmount,
            debtAmount
        );
        emit Data.SendToken(_msgSender(), id, tokenAmount);
    }

    function _repay(
        bytes32 id,
        bytes32 chainId,
        address user,
        uint256 tokenAmount
    ) internal {
        (uint256 repayAmount, uint256 debtAmount, uint256 ceAmount) = ICore(
            core
        ).repay(id, chainId, user, tokenAmount);
        emit Data.Repay(user, id, chainId, repayAmount, debtAmount, ceAmount);
        emit Data.ReceiveToken(user, id, tokenAmount);
    }

    function _deposit(
        bytes32 id,
        bytes32 chainId,
        address user,
        uint256 tokenAmount
    ) internal {
        uint256 ceAmount = ICore(core).deposit(id, chainId, user, tokenAmount);
        emit Data.Deposit(user, id, chainId, tokenAmount, ceAmount);
        emit Data.ReceiveToken(user, id, tokenAmount);
    }

    function _swap(
        bytes32 id,
        bytes32 srcChainId,
        bytes32 destChainId,
        uint256 tokenAmount
    ) internal {
        ICore(core).swap(id, srcChainId, destChainId, tokenAmount);
        emit Data.Swap(id, srcChainId, destChainId, tokenAmount);
    }

    function execute(
        bytes memory _payload,
        bytes32 chainId
    ) external onlyRole(IRoleManager(roleManager).ADAPTER()) {
        bytes32 tokenId;
        bytes32 data;
        uint64 amountpx;
        uint64 amountsx;
        uint8 functionType = uint8(_payload[0]); // _payload received is encoded in format (uint8, bytes32, bytes32, uint64, uint64)
        assembly {
            tokenId := mload(add(_payload, 33))
            data := mload(add(_payload, 65))
            amountpx := mload(add(_payload, 73))
            amountsx := mload(add(_payload, 81))
        }

        uint256 amount = uint256(amountpx) * BASE + uint256(amountsx);
        if (functionType == TYPE_DEPOSIT) {
            _deposit(tokenId, chainId, _bytesToAddress(data), amount);
        } else if (functionType == TYPE_REPAY) {
            _repay(tokenId, chainId, _bytesToAddress(data), amount);
        } else if (functionType == TYPE_SWAP) {
            _swap(tokenId, chainId, data, amount);
        } else {
            revert(string.concat(TAG, "Unsupport functionType"));
        }
    }

    function _bytesToAddress(bytes32 bys) private pure returns (address addr) {
        return address(uint160(uint256(bys)));
    }
}
