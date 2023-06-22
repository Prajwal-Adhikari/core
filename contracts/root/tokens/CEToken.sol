// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "../interfaces/IRoleManager.sol";
import "../interfaces/ICore.sol";

string constant TAG = "CEToken";

contract CEToken is ERC20Upgradeable {
    using SafeMathUpgradeable for uint256;
    address public core;
    address public roleManager;
    bytes32 public poolId;
    uint256 public transferBlockWait; //amount of blocks to wait before user can transfer minted ceToken
    uint256 public lockupTriggerAmt; //amount where lockup will kick in after cross-chain transfer
    mapping(address => uint256) public transferBlockRelease; //Block number

    error TransferTooSoonAfterMint(uint256 currentBlock, uint256 expectToExceedBlock);
    error UserIsCaged(address toUser);
    error BurnTooSoonAfterMint(uint256 currentBlock, uint256 expectToExceedBlock);
    
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

    function initialize(
        string memory name_,
        string memory symbol_,
        address roleManagerAddress
    ) public initializer {
        __ERC20_init( name_, symbol_);
        roleManager = roleManagerAddress;
    }

    function setRoleManager(address roleManagerAddress) external onlyRole(IRoleManager(roleManager).DEFAULT_ADMIN_ROLE()) {
        roleManager = roleManagerAddress;
    }

    function setCore(
        address coreAddress,
        bytes32 id
    ) external onlyRole(IRoleManager(roleManager).SET_CE_TOKEN_METHOD()) {
        core = coreAddress;
        poolId = id;
    }


    function setTransferBlockWait(uint256 num) external onlyRole(IRoleManager(roleManager).SET_CE_TOKEN_METHOD()) {
        transferBlockWait = num;
    }

    function setTransferBlockRelease(
        address user,
        uint256 blockNumber
    ) external onlyRole(IRoleManager(roleManager).CONTROLLER()) {
        transferBlockRelease[user] = blockNumber;
    }

    function setLockupTriggerAmount(uint256 amount) external onlyRole(IRoleManager(roleManager).SET_CE_TOKEN_METHOD()) {
        lockupTriggerAmt = amount;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        // require(
        //     block.number > transferBlockRelease[from],
        //     string.concat(TAG,": transfer too soon after cross-chain mint")
        // );

        if(block.number <= transferBlockRelease[from])
            revert TransferTooSoonAfterMint(block.number, transferBlockRelease[from]);

        uint ceScaled = ICore(core).getCEScaled(poolId);
        super._transfer(from, to, amount.mul(1e18).div(ceScaled));
        ICore(core).handleTransfer(from, to, poolId);
    }

    function balanceBeforeScaled(address user) external view returns (uint256) {
        return super.balanceOf(user);
    }

    function balanceOf(address user) public view override returns (uint256) {
        uint ceScaled = ICore(core).getCEScaled(poolId);
        return super.balanceOf(user) * ceScaled / 1e18;
    }

    function mint(address to, uint256 amount) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        // require(
        //     transferBlockRelease[to] != 2 ** 256 - 1,
        //     string.concat(TAG,": User is already caged")
        // );

        if( transferBlockRelease[to] == 2 ** 256 - 1)
            revert UserIsCaged(to);

        if (amount > lockupTriggerAmt) {
            transferBlockRelease[to] = block.number + transferBlockWait;
        }
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        // require(
        //     block.number > transferBlockRelease[from],
        //     string.concat(TAG,": burn too soon after cross-chain mint")
        // );
        if(block.number <= transferBlockRelease[from])
            revert BurnTooSoonAfterMint(block.number, transferBlockRelease[from]);

        _burn(from, amount);
    }

}
