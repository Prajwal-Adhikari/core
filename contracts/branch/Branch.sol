// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

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

string constant TAG = "Branch";

/**
 * Title Branch
 * Branch is deployed on all the chains Cedro supports.
 * It hosts the liquidity pools for all the pools listed in Cedro on that chain.
 * All the Branches are connected to Root, all of which sends deposit and repay information
 * to Root.
 * Users interact with Branch for Deposit and Repay actions.
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

    // Toggle to enable swap for Stargate cross chain liquidity transfer
    bool public swapDisable;

    /**
     * Mapping LayerZero's chain id to Cedro's chain id for a chain
     * Example: 10112 ->  keccak256("FTM")
     **/
    mapping(uint16 => bytes32) public chainId;

    event SendToken(address user, bytes32 id, uint256 tokenAmount);
    event ReceiveToken(address user, bytes32 id, uint256 tokenAmount);

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

    // Set contract addresses
    function setRoleManager(
        address roleManagerAddress
    ) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    function setAdapter(
        address adapterAddress
    ) external onlyRole(IRoleManager(roleManager).SET_BRANCH_METHOD()) {
        adapter = adapterAddress;
    }

    function setStargateRouterAndVault(
        address routerAddress,
        address vaultAddress
    ) external onlyRole(IRoleManager(roleManager).SET_BRANCH_METHOD()) {
        stargateRouter = routerAddress;
        stargateEthVault = vaultAddress;
    }

    function setForwarder(
        address forwarderAddress
    ) external onlyRole(IRoleManager(roleManager).SET_BRANCH_METHOD()) {
        _setTrustedForwarder(forwarderAddress);
    }

    function setPool(
        bytes32 id,
        address token,
        bool enable
    ) external onlyRole(IRoleManager(roleManager).SET_POOL()) {
        PoolInfo storage pool = pools[id];
        pool.enable = enable;
        pool.token = token;
    }

    // Methods to set pause
    function setDepositPause(
        bytes32 id,
        bool status
    ) external onlyRole(IRoleManager(roleManager).PROTOCOL_PAUSE()) {
        depositPause[id] = status;
    }

    function setRepayPause(
        bytes32 id,
        bool status
    ) external onlyRole(IRoleManager(roleManager).PROTOCOL_PAUSE()) {
        repayPause[id] = status;
    }

    function toggleProtocolStatus()
        external
        onlyRole(IRoleManager(roleManager).PROTOCOL_PAUSE())
    {
        protocolPause = !protocolPause;
    }

    function toggleSwapStatus()
        external
        onlyRole(IRoleManager(roleManager).SWAP())
    {
        swapDisable = !swapDisable;
    }

    function setChainId(
        bytes32 chainID, // Cedro's chain id
        uint16 id // LayerZero chain id
    ) external onlyRole(IRoleManager(roleManager).SET_BRANCH_METHOD()) {
        chainId[id] = chainID;
    }

    function depositRequest(
        bytes32 id,
        uint256 amount,
        bytes32 route,
        uint256 airdropAmount
    ) external payable nonReentrant {
        require(
            !(depositPause[id] || protocolPause),
            string.concat(TAG, ": Deposit paused")
        );
        require(pools[id].enable, string.concat(TAG, ": Pool not enable"));
        _pay(pools[id].token, amount, id, TYPE_DEPOSIT, route, airdropAmount);
        emit SendToken(msg.sender, id, amount);
    }

    function repayRequest(
        bytes32 id,
        uint256 amount,
        bytes32 route,
        uint256 airdropAmount
    ) external payable nonReentrant {
        require(
            !(repayPause[id] || protocolPause),
            string.concat(TAG, ": Deposit paused")
        );
        require(pools[id].enable, string.concat(TAG, ": Pool not enable"));
        _pay(pools[id].token, amount, id, TYPE_REPAY, route, airdropAmount);
        emit SendToken(msg.sender, id, amount);
    }

    function swapRequest(
        uint256 qty,
        bytes32 id,
        uint16 dstChainId,
        uint16 srcPoolId,
        uint16 dstPoolId,
        address destination,
        bytes32 route,
        uint256 fee
    ) external payable onlyRole(IRoleManager(roleManager).SWAP()) {
        require(
            msg.value > 0 && fee > 0,
            string.concat(
                TAG,
                ": requires a msg.value to pay crosschain message"
            )
        );
        require(
            qty > 0,
            string.concat(TAG, ": error: swap() requires qty > 0")
        );

        /**
         * Disable swap is done in case of a Stargate swap failure tx
         * only to update core contract values without doing actual swap through Stargate
         * to reverse the previous liquidity change made in case of swap failure through Adapter
         **/
        if (!swapDisable) {
            uint256 messageFee;
            if (pools[id].token == address(0)) {
                require(
                    msg.value > qty - fee,
                    string.concat(TAG, "msg.value must be > qty")
                );

                // wrap the ETH into WETH
                IStargateEthVault(stargateEthVault).deposit{value: qty}();
                IStargateEthVault(stargateEthVault).approve(
                    stargateRouter,
                    qty
                );

                messageFee = msg.value - qty - fee;
            } else {
                IERC20Upgradeable(pools[id].token).approve(stargateRouter, qty);
                messageFee = msg.value.sub(fee);
            }

            _swap(
                dstChainId,
                srcPoolId,
                dstPoolId,
                qty,
                destination,
                messageFee
            );
        }

        (uint64 amountpx, uint64 amountsx) = _buildRemoteAmount(qty, id);

        // Creating payload with required info to perform swap
        bytes memory payload = abi.encodePacked(
            TYPE_SWAP,
            id,
            chainId[dstChainId],
            amountpx,
            amountsx
        );

        // Sending `payload` to destination chain through chosen `route`
        IAdapter(adapter).send{value: fee}(payload, msg.sender, 0, route);
    }

    function emergencyWithdraw(
        bytes32 id,
        uint256 amount,
        address to
    ) external onlyRole(IRoleManager(roleManager).EMERGENCY_WITHDRAW()) {
        address token = pools[id].token;
        if (token == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20Upgradeable(token).safeTransfer(to, amount);
        }
    }

    function transferToken(
        bytes memory payload
    ) external onlyRole(IRoleManager(roleManager).ADAPTER()) {
        require(
            !protocolPause,
            string.concat(TAG, ": Token transfer is halted")
        );
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
        uint256 amount = uint256(amountpx) * BASE + uint256(amountsx);
        address token = pools[id].token;
        address receipient = address(uint160(uint256(to)));
        if (token == address(0)) {
            payable(receipient).transfer(amount);
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
        (uint64 amountpx, uint64 amountsx) = _buildRemoteAmount(amount, id);
        bytes memory payload = abi.encodePacked(
            functionType,
            id,
            addressToBytes32(msg.sender),
            amountpx,
            amountsx
        );
        if (token == address(0)) {
            require(msg.value >= amount, string.concat(TAG, "Invalid amount"));
            IAdapter(adapter).send{value: msg.value.sub(amount)}(
                payload,
                msg.sender,
                airdropAmount,
                route
            );
        } else {
            IERC20Upgradeable(token).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
            IAdapter(adapter).send{value: msg.value}(
                payload,
                msg.sender,
                airdropAmount,
                route
            );
        }
    }

    /**
     * @dev Swaps liquidity across chain using Stargate Protocol
     * @param dstChainId - chain id of destination
     * @param srcPoolId - pool id of source token in Stargate
     * @param dstPoolId - pool id of destination token in Stargate
     * @param qty - amount to be swapped
     * @param destination - address of the receiver
     * @param fee - communication protocol fee
     **/
    function _swap(
        uint16 dstChainId,
        uint16 srcPoolId,
        uint16 dstPoolId,
        uint256 qty,
        address destination,
        uint256 fee
    ) internal {
        IStargateRouter(stargateRouter).swap{value: fee}(
            dstChainId, // the destination chain id
            srcPoolId, // the source Stargate poolId
            dstPoolId, // the destination Stargate poolId
            payable(msg.sender), // refund adddress. if msg.sender pays too much gas, return extra eth
            qty, // total tokens to send to destination chain
            0, // min amount allowed out
            IStargateRouter.lzTxObj(0, 0, "0x"), // default lzTxObj
            abi.encodePacked(destination), // destination address, the sgReceive() implementer
            bytes("") // bytes payload
        );
    }

    function addressToBytes32(address addr) public pure returns (bytes32) {
        bytes32 result;
        assembly {
            mstore(0, addr)
            result := mload(0)
        }
        return result;
    }

    /**
     * @dev split the amount into 2 uint64 number to fix other not evm branch like aptos witch not support uint256 and keep the message send to root chain in the same format
     * For example 123456789000000000987654321 = 123456789 * 1e18 + 987654321
     * @param _localAmount the amount in evm branch
     * @param _id the pool id to get the token decimal
     **/
    function _buildRemoteAmount(
        uint256 _localAmount,
        bytes32 _id
    ) internal view returns (uint64 amountpx, uint64 amountsx) {
        (, bytes memory data) = pools[_id].token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        uint8 decimal = abi.decode(data, (uint8));
        _localAmount = decimal > ROOT_DECIMALS
            ? _localAmount / (10 ** (decimal - ROOT_DECIMALS))
            : _localAmount * (10 ** (ROOT_DECIMALS - decimal));
        amountpx = uint64(_localAmount / BASE);
        amountsx = uint64(_localAmount % BASE);
    }
}
