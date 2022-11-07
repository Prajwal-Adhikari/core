// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../layerZero/lzApp/NonblockingLzApp.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// todo
// 1.decimal
// 2.emergency withdraw

contract Client is LzApp {
    uint8 internal constant TYPE_DEPOSIT = 1;
    uint8 internal constant TYPE_REPAY = 2;

    uint public GAS_USAGE = 200000;
    uint16 public serverChainId;
    using SafeERC20 for IERC20;

    struct PoolInfo {
        bool enable;
        address token;
    }

    mapping(bytes32 => PoolInfo) public pools;

    constructor(address _lzEndpoint, uint16 _serverChainId) LzApp(_lzEndpoint) {
        serverChainId = _serverChainId;
    }

    function setPool(bytes32 id, address token, bool enable) external onlyOwner {
        PoolInfo storage pool = pools[id];
        if(pool.token == address(0)) {
            pool.token = token;
        }
        pool.enable = enable;
    }

    function setGasUsage(uint _usage) external {
        GAS_USAGE = _usage;
    }

    function estimateFees(uint8 functionType) public view returns (uint) {
        bytes memory payload = "";
        if(functionType == TYPE_DEPOSIT) {
            payload = abi.encode(TYPE_DEPOSIT, 1, msg.sender, 1);
        } else if(functionType == TYPE_REPAY) {
            payload = abi.encode(TYPE_REPAY, 1, msg.sender, 1);
        } else {
            revert("Unsupport functionType");
        }

        (uint fees, ) = lzEndpoint.estimateFees(serverChainId, address(this), payload, false, abi.encodePacked(bytes32(""), GAS_USAGE));
        return fees;
    }

    function depositRequest(bytes32 id, uint amount) external payable {
        require(pools[id].enable, "Pool not enable");
        IERC20(pools[id].token).safeTransferFrom(msg.sender, address(this), amount);
        bytes memory payload = abi.encode(TYPE_DEPOSIT, id, msg.sender, amount);
        _send(serverChainId, payload);
    }

    function repayRequest(bytes32 id, uint amount) external payable {
        require(pools[id].enable, "Pool not enable");
        IERC20(pools[id].token).safeTransferFrom(msg.sender, address(this), amount);
        bytes memory payload = abi.encode(TYPE_REPAY, id, msg.sender, amount);
        _send(serverChainId, payload);
    }

    function _send(uint16 chainId, bytes memory payload) internal {
        _lzSend(chainId, payload, payable(msg.sender), address(this), abi.encodePacked(uint16(1), GAS_USAGE));
    }

    function _blockingLzReceive(uint16, bytes memory, uint64, bytes memory _payload) internal override {
        (bytes32 id, address user, uint amount) = abi.decode(_payload, (bytes32, address, uint256));
        IERC20(pools[id].token).safeTransfer(user, amount);
    }
}
