// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ICore.sol";
import "../interfaces/IRoleManager.sol";

string constant TAG = "CEToken";

contract CEToken is ERC20, Ownable {
    address public core;
    address public roleManager;
    uint256 public transferBlockWait; //amount of blocks to wait before user can transfer minted ceToken
    uint256 public lockupTriggerAmt; //amount where lockup will kick in after cross-chain transfer
    mapping(address => uint256) public transferBlockRelease; //Block number

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {}

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

    function setCore(
        address coreAddress
    ) external onlyRole(IRoleManager(roleManager).SET_CE_TOKEN_METHOD()) {
        core = coreAddress;
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
        require(
            block.number > transferBlockRelease[from],
            string.concat(TAG,": transfer too soon after cross-chain mint")
        );
        super._transfer(from, to, amount);
        ICore(core).checkHealth(from);
    }

    function mint(address to, uint256 amount) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        if (amount > lockupTriggerAmt) {
            transferBlockRelease[to] = block.number + transferBlockWait;
        }
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        require(
            block.number > transferBlockRelease[from],
            string.concat(TAG,": burn too soon after cross-chain mint")
        );
        _burn(from, amount);
    }

}
