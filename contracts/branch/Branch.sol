// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../layerZero/lzApp/LzApp.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IAdapter.sol";
import "./interfaces/IStargateRouter.sol";
import "./interfaces/IStargateEthVault.sol";
import "./interfaces/IRoleManager.sol";

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
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint8 internal constant TYPE_DEPOSIT = 1;
    uint8 internal constant TYPE_REPAY = 2;
    uint8 internal constant TYPE_SWAP = 3;

    uint256 public constant ROOT_DECIMALS = 18;
    uint256 public constant BASE = 10 ** ROOT_DECIMALS;

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public roleManager;
    address public adapter;
    address public stargateRouter;
    address public stargateEthVault;
    bool public swapDisable;

    mapping(uint16 => bytes32) public chainName;
    mapping(bytes32 => bool) public depositPause;
    mapping(bytes32 => bool) public repayPause;
    bool public protocolPause;

    struct PoolInfo {
        bool enable;
        address token;
    }

    mapping(bytes32 => PoolInfo) public pools;

    event SendToken(address user, bytes32 id, uint256 tokenAmount);

    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /**
     * @dev Modifier that checks if caller has a specific role.
     **/
    modifier onlyRole(bytes32 role) {
        IRoleManager(roleManager).checkRole(role, _msgSender());
        _;
    }

    function setRoleManager(address roleManagerAddress) external onlyOwner {
        roleManager = roleManagerAddress;
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

    /**
     * @dev Links chainId with chain name.
     * This function can only be accessed by the contract owner.
     * @param chain name of the chain.
     * @param id chain id of the chain.
     **/
    function setChainName(
        bytes32 chain,
        uint16 id
    ) external onlyRole(IRoleManager(roleManager).SET_BRANCH_METHOD()) {
        chainName[id] = chain;
    }

    /**
     * @dev sends a deposit information message to the Root.
     * @param id pool id of the pool of the deposited amount
     * @param amount amount deposited in the pool
     * @param route communication protocol
     **/
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
    }

    /**
     * @dev sends a repay information message to the Root.
     * @param id pool id of the pool of the repaid amount
     * @param amount amount repaid in the pool
     **/
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
                IERC20(pools[id].token).approve(stargateRouter, qty);
                messageFee = msg.value - fee;
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
        bytes memory payload = abi.encodePacked(
            TYPE_SWAP,
            id,
            chainName[dstChainId],
            amountpx,
            amountsx
        );

        IAdapter(adapter).send{value: fee}(payload, msg.sender, 0, route);
    }

    

    /**
     * @dev emergency function to withdraw liquidity
     * @param id token address to withdraw
     * @param amount amount of token to withdraw
     * @param to receiver address
     **/
    function emergencyWithdraw(
        bytes32 id,
        uint256 amount,
        address to
    ) external onlyRole(IRoleManager(roleManager).EMERGENCY_WITHDRAW()) {
        address token = pools[id].token;
        if (token == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    

    function transferToken(
        bytes memory payload
    ) external onlyRole(IRoleManager(roleManager).ADAPTER()) {
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
        if (token == address(0)) {
            payable(address(uint160(uint256(to)))).transfer(amount);
        } else {
            IERC20(token).safeTransfer(address(uint160(uint256(to))), amount);
        }
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
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            IAdapter(adapter).send{value: msg.value}(
                payload,
                msg.sender,
                airdropAmount,
                route
            );
        }
        emit SendToken(msg.sender, id, amount);
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
