// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
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

string constant TAG = "Pool";

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
    bool public rewardEnable;

    error ProtocolPaused(string contractTAG);
    error UnsupportedFunctionType(string contractTAG, uint8 functionType);
    error WithdrawPaused(string contractTAG, bytes32 chainId, bytes32 id);
    error BorrowPaused(string contractTAG, bytes32 chainId, bytes32 id);
    error BadPayload(string contractTAG, uint256 currentLength, uint256 requiredLength);
    error InvalidTokenAmount(string contractTAG);
	error InvalidRatio(string contractTAG);
    error InvalidLoopCount(string contractTAG);


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
     * @param roleManagerAddress - Address of the roleManager contract.
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
     * @notice Configures reward status.
     * This function can only be accessed by the account with role SET_POOL_METHOD
     **/ 
    function toggleRewardEnable()
        external
        onlyRole(IRoleManager(roleManager).SET_POOL_METHOD())
    {
        rewardEnable = !rewardEnable;
    }

    /**
     * @notice Sends a withdraw request of amount `ceAmount` to address `to` from pool with pool id `id`
     * in chain with chain id `chainId` to core contract
     * This function can be accessed by anyone
     * @param id - pool id of pool to withdraw from
     * @param chainId - chain id of chain to withdraw from
     * @param tokenAmount - amount to withdraw
     * @param to - withdraw address
     * @param route - communication protocol
     * @param airdropAmount - amount to be airdropped to destination chain
     * @param all - true if withdraw all
     **/
    function withdraw(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount,
        bytes32 to,
        bytes32 route,
        uint256 airdropAmount,
        bool all
    ) external payable nonReentrant {

        if(tokenAmount == 0)
            revert InvalidTokenAmount(TAG);
  
        if(protocolPause)
            revert ProtocolPaused(TAG);

        if(withdrawPause[id][chainId])
            revert WithdrawPaused(TAG, chainId, id);

        uint256 fee;
        if(all) {
            tokenAmount = ICore(core).getWithdrawableBalancePerPool(id,_msgSender());
        }
        if(feeEnable) {
            fee = IFeeProvider(feeProvider).setFeeAmount(chainId, id, tokenAmount);
            
        }

        (uint256 burnAmount, uint256 actualAmount) = ICore(core).withdraw(
            id,
            chainId,
            tokenAmount,
            _msgSender(),
            all
        );

        actualAmount -= fee;

        bytes memory payload = abi.encodePacked(
            id,
            to,
            actualAmount
        );
        if(payload.length != 96)
            revert BadPayload(TAG, payload.length, 96);

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
            burnAmount,
            route,
            fee
        );
        emit Data.SendToken(_bytesToAddress(to), id, actualAmount);
    }

    /**
     * @notice Sends a withdraw request of amount `tokenAmount` of dead tokens to address `user` from pool with pool id `id`
     * in chain with chain id `chainId`
     * This function can be accessed by anyone
     * @param id - pool id of pool to withdraw from
     * @param chainId - chain id of chain to withdraw from
     * @param tokenAmount - amount to withdraw
     * @param to - withdraw address
     * @param route - communication protocol
     * @param airdropAmount - amount to be airdropped to destination chain
     * @param all - true if withdraw all
     **/
     function withdrawDeadTokens(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount,
        bytes32 to,
        bytes32 route,
        uint256 airdropAmount,
        bool all
    ) external payable nonReentrant {

        if(tokenAmount == 0)
            revert InvalidTokenAmount(TAG);

        if(protocolPause)
            revert ProtocolPaused(TAG);

        (uint256 burnAmount, uint256 actualAmount) = ICore(core).withdrawDeadTokens(
            id,
            chainId,
            tokenAmount,
            _msgSender(),
            all
        );

        bytes memory payload = abi.encodePacked(
            id,
            to,
            actualAmount
        );

        if(payload.length != 96)
            revert BadPayload(TAG, payload.length, 96);

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
            burnAmount,
            route,
            0
        );
        emit Data.SendToken(_bytesToAddress(to), id, actualAmount);
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

        if(tokenAmount == 0)
            revert InvalidTokenAmount(TAG);

        if(protocolPause)
            revert ProtocolPaused(TAG);

        if(borrowPause[id][chainId])
            revert BorrowPaused(TAG, chainId, id);

        uint256 fee;
        if (feeEnable) {
            fee = IFeeProvider(feeProvider).setFeeAmount(chainId, id, tokenAmount);
        }

        (uint256 debtAmount, uint256 actualAmount) = ICore(core).borrow(
            id,
            chainId,
            tokenAmount,
            _msgSender()
        );

        actualAmount -= fee;

        bytes memory payload = abi.encodePacked(
            id,
            to,
            actualAmount
        );
        if(payload.length != 96)
            revert BadPayload(TAG, payload.length, 96);

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
            route,
            fee
        );
        emit Data.SendToken(_bytesToAddress(to), id, actualAmount);
    }

    /**
     * @notice Leverager method looping deposit and borrow of an asset
     * This function can be accessed by anyone
     * @param id - pool id of pool to borrow from
     * @param chainId - chain id of chain to borrow from
     * @param tokenAmount - total amount to loop
     * @param borrowRatio - ratio of tokens to borrow
     * @param loopCount - repeat count for loop
     **/
    function loop(
        bytes32 id,
        bytes32 chainId,
        uint256 tokenAmount,
        uint256 borrowRatio,
        uint256 loopCount
    ) external nonReentrant {

        if(tokenAmount == 0)
            revert InvalidTokenAmount(TAG);

        if (!(borrowRatio > 0 && borrowRatio <= 1e18))
            revert InvalidRatio(TAG);
            
        if (loopCount == 0)
            revert InvalidLoopCount(TAG);
        
        uint256 debtAmount;
        uint256 ceAmount;
        for (uint256 i = 0; i < loopCount; ) {
            tokenAmount = tokenAmount.mul(borrowRatio).div(1e18);
            uint256 fee;
            if (feeEnable) {
                fee = IFeeProvider(feeProvider).setFeeAmount(chainId, id, tokenAmount);
            }

            (debtAmount, tokenAmount) = ICore(core).borrow(
                id,
                chainId,
                tokenAmount,
                _msgSender()
            );

            emit Data.Borrow(
            _msgSender(),
            _msgSender(),
            id,
            chainId,
            tokenAmount,
            debtAmount,
            "",
            fee
            );
            
            tokenAmount -= fee;
            uint256 reward;
            if (rewardEnable) {
                reward = IFeeProvider(feeProvider).setRewardAmount(chainId, id, tokenAmount);
            }

            tokenAmount += reward;
            ( ceAmount, tokenAmount) = ICore(core).deposit(id, chainId, _msgSender(), tokenAmount);

            emit Data.Deposit(_msgSender(), id, chainId, tokenAmount.sub(reward), ceAmount, "", reward);
            unchecked {
				i++;
			}

        }
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
        uint256 reward;
        if (rewardEnable) {
            reward = IFeeProvider(feeProvider).setRewardAmount(chainId, id, tokenAmount);
        }

        (uint256 repayAmount, uint256 debtAmount, uint256 ceAmount) = ICore(core).repay(id, chainId, user, tokenAmount.add(reward));
        emit Data.Repay(user, id, chainId, repayAmount.sub(reward), debtAmount, ceAmount, route, reward);
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
    ) internal nonReentrant {
        uint256 reward;
        if (rewardEnable) {
            reward = IFeeProvider(feeProvider).setRewardAmount(chainId, id, tokenAmount);
        }
        (uint256 ceAmount, uint256 actualAmount) = ICore(core).deposit(id, chainId, user, tokenAmount.add(reward));
        
        emit Data.Deposit(user, id, chainId, actualAmount.sub(reward), ceAmount, route, reward);
        emit Data.ReceiveToken(user, id, tokenAmount);
    }

     /**
     * @notice Swaps liquidity amount from one chain to another
     * This function can only be accessed by account with role SWAP.
     * @param id - pool id of the asset.
     * @param srcChainId - chain id of the source chain
     * @param destChainId - chain id of the destination chain
     * @param tokenAmountInSrc - liquidity amount sent from source chain
     * @param tokenAmountInDest - liquidity amount received to destination chain
     **/
    function swap(
        bytes32 id,
        bytes32 srcChainId,
        bytes32 destChainId,
        uint256 tokenAmountInSrc,
        uint256 tokenAmountInDest
    ) external onlyRole(IRoleManager(roleManager).SWAP()) {
        uint256 reward;
        if (rewardEnable) {
            reward = IFeeProvider(feeProvider).setRewardAmountForSwap(destChainId, id, tokenAmountInDest);
        }
        ICore(core).swap(id,srcChainId,destChainId,tokenAmountInSrc,tokenAmountInDest);
        emit Data.Swap(reward);
        
    }

    /**
     * @notice Sets the status of the collateral usage of the depositor
     * This function can only be accessed by the account with role POOL.
     * @param poolId - id of the pool to change the status of
     * @param status - status if true collateral usage is disabled
     **/
    function disableCollateralUsage(
        bytes32 poolId,
        bool status
    ) external {
        ICore(core).disableCollateralUsage(_msgSender(), poolId, status);
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
        uint256 amount;
        if(_payload.length != 97)
            revert BadPayload(TAG, _payload.length, 97);
        
        uint8 functionType = uint8(_payload[0]); // _payload received is encoded in format (uint8, bytes32, bytes32, uint256)
        assembly {
            tokenId := mload(add(_payload, 33))
            data := mload(add(_payload, 65))
            amount := mload(add(_payload, 97))
        }

        if (functionType == TYPE_DEPOSIT) {
            _deposit(tokenId, chainId, _bytesToAddress(data), amount, route);
        } else if (functionType == TYPE_REPAY) {
            _repay(tokenId, chainId, _bytesToAddress(data), amount, route);
        } else {
            revert UnsupportedFunctionType(TAG, functionType);
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