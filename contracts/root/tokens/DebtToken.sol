// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IRoleManager.sol";

string constant TAG = "DebtToken";

contract DebtToken is ERC20, Ownable {
    address public roleManager;
    uint256 public balanceScale = 1e18;
    uint256 public constant MAG = 1e18;

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



    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal pure override {
        (from, to, amount);
        require(false, string.concat(TAG,": Cannot transfer debt token"));
    }

    function mint(address to, uint256 amount) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(IRoleManager(roleManager).MINT_BURN_CE_DEBT_TOKEN()) {
        _burn(from, amount);
    }
}
