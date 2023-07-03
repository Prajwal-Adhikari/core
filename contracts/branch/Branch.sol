// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./interfaces/IAdapter.sol";
import "./interfaces/IStargateRouter.sol";
import "./interfaces/IStargateEthVault.sol";
import "./interfaces/IRoleManager.sol";
import "../utils/ERC2771ContextUpgradeable.sol";

/**
 * @title Branch
 * @notice Branch is deployed on all the chains Cedro supports.
 * @notice It hosts the liquidity pools for all the pools listed in Cedro on that chain.
 * @notice All the Branches are connected to Root, all of which sends deposit and repay information to Root.
 * @notice Users interact with Branch for Deposit and Repay actions.
 **/
contract Branch is
    Initializable,
    ReentrancyGuardUpgradeable,
    ERC2771ContextUpgradeable
{
    // Request types
    uint8 internal constant TYPE_DEPOSIT = 1;
    uint8 internal constant TYPE_REPAY = 2;
    uint8 internal constant TYPE_SWAP = 3;

    uint256 public constant ROOT_DECIMALS = 18;
    uint256 public constant BASE = 10 ** ROOT_DECIMALS;

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    address public roleManager;
    address public adapter;

    //Addresses to be set before performing a Stargate swap
    address public stargateRouter;
    address public stargateEthVault;

    struct PoolInfo {
        bool enable;
        address token;
    }

    // key: poolId
    // Example poolId = keccak256("USDC") for USDC pool
    // poolId for an asset must be same in all branch and root contracts
    mapping(bytes32 => PoolInfo) public pools;

    // key: poolId
    // Pool level pause
    mapping(bytes32 => bool) public depositPause;
    mapping(bytes32 => bool) public repayPause;

    // Protocol level pause for all pools
    bool public protocolPause;

    event SendToken(address user, bytes32 id, uint256 tokenAmount);
    event ReceiveToken(address user, bytes32 id, uint256 tokenAmount);
    event Deposit(
        address user,
        bytes32 id,
        uint256 tokenAmount,
        bytes32 route,
        uint256 aidrdropAmount
    );
    event Repay(
        address user,
        bytes32 id,
        uint256 tokenAmount,
        bytes32 route,
        uint256 aidrdropAmount
    );

    error InsufficientValue(uint contractCode, uint256 valueSent, uint256 valueToBeGreater);
    error InsufficientQuantity(uint contractCode);
    error DepositPaused(uint contractCode, bytes32 poolID);
    error ProtocolPaused(uint contractCode);
    error NativeTransferFailed(uint contractCode);
    error BadPayload(uint contractCode, uint256 currentLength, uint256 requiredLength);
    error PoolNotEnabled(uint contractCode, bytes32 poolID);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Sets the roleManager address.
     * @param forwarder - Address of the forwarder.
     * @param roleManagerAddress - Role manager address.
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
     * @dev Modifier that checks if caller has a specific role.
     **/
    modifier onlyRole(bytes32 role) {
        IRoleManager(roleManager).checkRole(role, _msgSender());
        _;
    }

    /**
     * @notice Configures role manager address
     * This function can only be accessed by the account with role DEFAULT_ADMIN_ROLE.
     * @param roleManagerAddress - address of the roleManager contract.
     **/
    function setRoleManager(
        address roleManagerAddress
    ) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    /**
     * @notice Configures adapter contract.
     * This function can only be accessed by account with role SET_BRANCH_METHOD.
     * @param adapterAddress - address of the adapter contract.
     **/
    function setAdapter(
        address adapterAddress
    ) external onlyRole(IRoleManager(roleManager).SET_BRANCH_METHOD()) {
        adapter = adapterAddress;
    }

    /**
     * @notice Configures router address for swap.
     * This function can only be accessed by account with role SET_BRANCH_METHOD.
     * @param routerAddress - address of the  Stargate router contract.
     * @param vaultAddress - address of the  Stargate vault contract.
     **/
    function setStargateRouterAndVault(
        address routerAddress,
        address vaultAddress
    ) external onlyRole(IRoleManager(roleManager).SET_BRANCH_METHOD()) {
        stargateRouter = routerAddress;
        stargateEthVault = vaultAddress;
    }

    /**
     * @notice Sets the forwarder address.
     * @param forwarderAddress - Forwarder address.
     **/
    function setForwarder(
        address forwarderAddress
    ) external onlyRole(IRoleManager(roleManager).SET_BRANCH_METHOD()) {
        _setTrustedForwarder(forwarderAddress);
    }

    /**
     * @notice Configures pool for an asset
     * This function can only be accessed by account with role SET_POOL.
     * @param id - pool id for the asset.
     * @param token - address of the asset.
     * @param enable - status of the pool
     **/
    function setPool(
        bytes32 id,
        address token,
        bool enable
    ) external onlyRole(IRoleManager(roleManager).SET_POOL()) {
        PoolInfo storage pool = pools[id];
        pool.enable = enable;
        pool.token = token;
    }

    /**
     * @notice Configures pool status for deposit
     * This function can only be accessed by account with role PROTOCOL_PAUSE.
     * @param id - pool id of the asset.
     * @param status - status of the pool.
     **/    
    function setDepositPause(
        bytes32 id,
        bool status
    ) external onlyRole(IRoleManager(roleManager).PROTOCOL_PAUSE()) {
        depositPause[id] = status;
    }

    /**
     * @notice Configures pool status for repay
     * This function can only be accessed by account with role PROTOCOL_PAUSE.
     * @param id - pool id of the asset.
     * @param status - status of the pool.
     **/
    function setRepayPause(
        bytes32 id,
        bool status
    ) external onlyRole(IRoleManager(roleManager).PROTOCOL_PAUSE()) {
        repayPause[id] = status;
    }

    /**
     * @notice Toggles the status of the protocol on and off.
     * This function can only be accessed by account with role PROTOCOL_PAUSE.
     **/
    function toggleProtocolStatus()
        external
        onlyRole(IRoleManager(roleManager).PROTOCOL_PAUSE())
    {
        protocolPause = !protocolPause;
    }

    /**
     * @notice Sends deposit information message to the Root.
     * This function can be accessed by the user.
     * @param id - pool id of the pool of the deposited amount
     * @param amount - amount deposited in the pool
     * @param route - communication protocol
     * @param  airdropAmount - amount to be airdropped to destination chain
     **/ 
    function depositRequest(
        bytes32 id,
        uint256 amount,
        bytes32 route,
        uint256 airdropAmount
    ) external payable nonReentrant {
        if(protocolPause)
            revert ProtocolPaused(3);
        if(depositPause[id])
            revert DepositPaused(3, id);
        if(! pools[id].enable)
            revert PoolNotEnabled(3, id);
        _pay(pools[id].token, amount, id, TYPE_DEPOSIT, route, airdropAmount);
        emit Deposit(_msgSender(), id, amount, route, airdropAmount);
        emit SendToken(_msgSender(), id, amount);
    }

    /**
     * @notice Sends repay information message to the Root.
     * This function can be accessed by the user.
     * @param id - pool id of the pool of the repaid amount
     * @param amount - amount repaid in the pool
     * @param route - communication protocol
     * @param  airdropAmount - amount to be airdropped to destination chain
     **/  
    function repayRequest(
        bytes32 id,
        uint256 amount,
        bytes32 route,
        uint256 airdropAmount
    ) external payable nonReentrant {
        if(protocolPause)
            revert ProtocolPaused(3);
        if(repayPause[id])
            revert DepositPaused(3, id);
        if(! pools[id].enable)
            revert PoolNotEnabled(3, id);
        _pay(pools[id].token, amount, id, TYPE_REPAY, route, airdropAmount);
        emit Repay(_msgSender(), id, amount, route, airdropAmount);
        emit SendToken(_msgSender(), id, amount);
    }

   /**
     * @notice Swaps liquidity across chain
     * This function can only be accessed by account with role SWAP.
     * @param qty - amount to be swapped
     * @param id - id of the pool
     * @param dstChainId - chain id of destination
     * @param srcPoolId - pool id of source token in Stargate
     * @param dstPoolId - pool id of destination token in Stargate
     * @param destination - address of the receiver     
     * @param amountMin - The minimum amount to receive.
     **/  
    function swapRequest(
        uint256 qty,
        bytes32 id,
        uint16 dstChainId,
        uint16 srcPoolId,
        uint16 dstPoolId,
        address destination,
        uint256 amountMin
    ) external payable onlyRole(IRoleManager(roleManager).SWAP()) {
        if(msg.value == 0)
            revert InsufficientValue(3, msg.value, 0);
        if(qty == 0)
            revert InsufficientQuantity(3);

        if (pools[id].token == address(0)) {
            // wrap the ETH into WETH
            IStargateEthVault(stargateEthVault).deposit{value: qty}();
            IStargateEthVault(stargateEthVault).approve(stargateRouter, qty);
        } else {
            IERC20Upgradeable(pools[id].token).approve(stargateRouter, qty);
        }

        IStargateRouter(stargateRouter).swap{value: msg.value}(
            dstChainId, // the destination chain id
            srcPoolId, // the source Stargate poolId
            dstPoolId, // the destination Stargate poolId
            payable(msg.sender), // refund adddress. if msg.sender pays too much gas, return extra eth
            qty, // total tokens to send to destination chain
            amountMin, // min amount allowed out
            IStargateRouter.lzTxObj(0, 0, "0x"), // default lzTxObj
            abi.encodePacked(destination), // destination address, the sgReceive() implementer
            bytes("") // bytes payload
        );
    }

    /**
     * @notice Emergency function to withdraw liquidity if case of any exploit
     * This function can only be accessed by account with role EMERGENCY_WITHDRAW.
     * @param id - token address to withdraw
     * @param amount - amount of token to withdraw
     * @param to - receipient address
     **/ 
    function emergencyWithdraw(
        bytes32 id,
        uint256 amount,
        address to
    ) external onlyRole(IRoleManager(roleManager).EMERGENCY_WITHDRAW()) {
        address token = pools[id].token;
        if (token == address(0)) {
            (bool sent, ) = payable(to).call{value: amount}("");
            if(! sent)
                revert NativeTransferFailed(3);
        } else {
            IERC20Upgradeable(token).safeTransfer(to, amount);
        }
    }

    /**
     * @notice Transfers token to the user.
     * This function can only be accessed by account with role ADAPTER.
     * @param payload - information containing token amount and receipient.
     **/
    function transferToken(
        bytes memory payload
    ) external onlyRole(IRoleManager(roleManager).ADAPTER()) {
        if(protocolPause)
            revert ProtocolPaused(3);

        if(payload.length != 80)
            revert BadPayload(3, payload.length, 80);

        bytes32 id;
        bytes32 to;
        uint64 amountpx;
        uint64 amountsx;
        assembly {
            id := mload(add(payload, 32))
            to := mload(add(payload, 64))
            amountpx := mload(add(payload, 72))
            amountsx := mload(add(payload, 80))
        }
        address token = pools[id].token;
        uint256 amount = _buildLocalAmount(amountpx, amountsx, token);
        address receipient = address(uint160(uint256(to)));
        if (token == address(0)) {
            (bool sent, ) = payable(receipient).call{value: amount}("");
            if(! sent)
                revert NativeTransferFailed(3);
        } else {
            IERC20Upgradeable(token).safeTransfer(receipient, amount);
        }
        emit ReceiveToken(receipient, id, amount);
    }

    /**
     * @dev send the deposited / repaid amount from user to the pool.
     * Called when contract receives deposit / repay request from an address.
     * @param token token address of the deposited / repaid token
     * @param amount amount of token deposited / repaid
     * @param id pool id of the pool
     * @param functionType type of function
     **/
    function _pay(
        address token,
        uint256 amount,
        bytes32 id,
        uint8 functionType,
        bytes32 route,
        uint256 airdropAmount
    ) internal {
        
        uint256 payAmount = _getPayAmount(
            amount,
            token
        );
        uint256 buildAmount;
        if (token == address(0)) {
            if(msg.value < payAmount)
                revert InsufficientValue(3, msg.value, payAmount-1);

            buildAmount = amount;
        } else {
            uint256 tokenBalanceBefore = IERC20Upgradeable(token).balanceOf(address(this));
            IERC20Upgradeable(token).safeTransferFrom(
                _msgSender(),
                address(this),
                payAmount
            );
            uint256 tokenBalanceAfter = IERC20Upgradeable(token).balanceOf(address(this));
            buildAmount = tokenBalanceAfter.sub(tokenBalanceBefore);
        }
        (uint64 amountpx, uint64 amountsx) = _buildRemoteAmount(
                buildAmount,
                token
        );
        bytes memory payload = abi.encodePacked(
            functionType,
            id,
            addressToBytes32(_msgSender()),
            amountpx,
            amountsx
        );
        if(payload.length != 81)
            revert BadPayload(3, payload.length, 81);

        if (token == address(0)) {
            IAdapter(adapter).send{value: msg.value.sub(payAmount)}(
                payload,
                msg.sender,
                airdropAmount,
                route
            );
        } else {
            IAdapter(adapter).send{value: msg.value}(
                payload,
                msg.sender,
                airdropAmount,
                route
            );
        }
    }

    /**
     * @notice Converts address to bytes32
     * @param addr - token address to withdraw
     **/
    function addressToBytes32(address addr) public pure returns (bytes32) {
        bytes32 result;
        assembly {
            mstore(0, addr)
            result := mload(0)
        }
        return result;
    }

    function _getTokenDecimal(
        address _token
    ) internal view returns (uint8 decimals) {
        decimals = 18;
        if (_token != address(0)) {
            (, bytes memory data) = _token.staticcall(
                abi.encodeWithSignature("decimals()")
            );
            decimals = abi.decode(data, (uint8));
        }
    }

    /**
     * @dev Combines the amount sent from the payload.
     * @param _amountpx The amount sent from payload.
     * @param _amountsx The amount sent from payload.
     * @param _token The token address.
     **/
    function _buildLocalAmount(
        uint256 _amountpx,
        uint256 _amountsx,
        address _token
    ) internal view returns (uint _localAmount) {
        uint _remoteAmount = uint256(_amountpx) * BASE + uint256(_amountsx);
        uint8 decimals = _getTokenDecimal(_token);
        _localAmount = decimals > ROOT_DECIMALS
            ? _remoteAmount * (10 ** (decimals - ROOT_DECIMALS))
            : _remoteAmount / (10 ** (ROOT_DECIMALS - decimals));
    }

    /**
     * @dev split the amount into 2 uint64 number to fix other not evm branch like aptos witch not support uint256 and keep the message send to root chain in the same format
     * For example 123456789000000000987654321 = 123456789 * 1e18 + 987654321
     * @param _localAmount the amount in evm branch
     * @param _token the token to get the token decimals
     **/
    function _buildRemoteAmount(
        uint256 _localAmount,
        address _token
    ) internal view returns (uint64 amountpx, uint64 amountsx) {
        uint8 decimals = _getTokenDecimal(_token);

        if (decimals > ROOT_DECIMALS) {
            _localAmount = _localAmount / (10 ** (decimals - ROOT_DECIMALS));
        } else {
            _localAmount = _localAmount * (10 ** (ROOT_DECIMALS - decimals));
        }

        amountpx = uint64(_localAmount / BASE);
        amountsx = uint64(_localAmount % BASE);
    }

    /**
     * @dev Get the amount to transfer in cross chain transactions.
     * @param _localAmount the amount to transfer in source chain.
     * @param _token the token to transfer.
     **/
    function _getPayAmount(
        uint256 _localAmount,
        address _token 
    ) internal view returns (uint256 amount) {
        uint8 decimals = _getTokenDecimal(_token);

        if (decimals > ROOT_DECIMALS) {
            //ignore decimals beyond the 18th digit
            amount =
                (_localAmount / (10 ** (decimals - ROOT_DECIMALS))) *
                10 ** (decimals - ROOT_DECIMALS);
        } else {
            amount = _localAmount;
        }
    }
}
