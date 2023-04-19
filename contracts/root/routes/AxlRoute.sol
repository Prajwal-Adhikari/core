// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AxelarExecutable} from "../../axelar/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "../../axelar/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "../../axelar/interfaces/IAxelarGasService.sol";
import "../interfaces/IAdapter.sol";

contract AxlRoutePool is Initializable, OwnableUpgradeable, AxelarExecutable {
    mapping(bytes32 => string) public destChain;
    mapping(bytes32 => string) public destAddress;
    mapping(bytes32 => bytes32) public chainName;
    mapping(bytes32 => bytes32) public trustedContract;

    address public adapter;

    uint8 internal constant TYPE_DEPOSIT = 1;
    uint8 internal constant TYPE_REPAY = 2;
    uint8 internal constant TYPE_SWAP = 3;

    uint public constant BASE = 10 ** 18;
    IAxelarGasService gasService;

    function initialize(
        address _gateway,
        address _gasReceiver
    ) public initializer {
        __AxelarExecutable_init(_gateway);
        __Ownable_init();
        gasService = IAxelarGasService(_gasReceiver);
    }

    event Executed();

    /**
     * @dev only adapter can use functions affected by this modifier
     **/
    modifier onlyAdapter() {
        require(adapter == msg.sender, "The caller must be a pool contract");
        _;
    }

    /**
     * @dev Configures adapter contract.
     * This function can only be accessed by the contract owner.
     * @param adapterAddress address of the adapter contract.
     **/
    function setAdapter(address adapterAddress) external onlyOwner {
        adapter = adapterAddress;
    }

    /**
     * @dev Links chain key with chain name and destination contract
     * This function can only be accessed by the contract owner.
     * @param chain key of the chain.
     * @param name name of the chain.
     * @param addr address of the destination contract
     **/
    function setDestChainNameAddress(
        bytes32 chain,
        string calldata name,
        string calldata addr
    ) external onlyOwner {
        destChain[chain] = name;
        destAddress[chain] = addr;
        chainName[keccak256(abi.encodePacked(name))] = chain;
        trustedContract[keccak256(abi.encodePacked(name))] = keccak256(
            abi.encodePacked(addr)
        );
    }

    function sendToken(
        bytes32 id,
        bytes32 chainId,
        bytes32 user,
        address sender,
        uint amount,
        uint
    ) external payable onlyAdapter {
        bytes memory payload = abi.encodePacked(
            id,
            user,
            uint64(amount / BASE),
            uint64(amount % BASE)
        );
        require(payload.length == 80, "Bad payload");
        if (msg.value > 0) {
            gasService.payNativeGasForContractCall{value: msg.value}(
                address(this),
                destChain[chainId],
                destAddress[chainId],
                payload,
                sender
            );
        }
        gateway.callContract(destChain[chainId], destAddress[chainId], payload);
    }

    function _execute(
        string calldata sourceChain_,
        string calldata sourceAddress_,
        bytes calldata payload_
    ) internal override {
        bytes32 chain = keccak256(abi.encodePacked(sourceChain_));
        bytes32 addr = keccak256(abi.encodePacked(sourceAddress_));
        require(trustedContract[chain] == addr, "Invalid contract");
        bytes32 tokenId;
        bytes32 data;
        uint64 amountpx;
        uint64 amountsx;

        bytes memory _payload = payload_;
        uint8 functionType = uint8(_payload[0]);
        assembly {
            tokenId := mload(add(_payload, 33))
            data := mload(add(_payload, 65))
            amountpx := mload(add(_payload, 73))
            amountsx := mload(add(_payload, 81))
        }

        uint amount = uint(amountpx) * BASE + uint(amountsx);
        if (functionType == TYPE_DEPOSIT) {
            IAdapter(adapter).deposit(
                tokenId,
                chainName[chain],
                _bytesToAddress(data),
                amount
            );
        } else if (functionType == TYPE_REPAY) {
            IAdapter(adapter).repay(
                tokenId,
                chainName[chain],
                _bytesToAddress(data),
                amount
            );
        } else if (functionType == TYPE_SWAP) {
            IAdapter(adapter).swap(tokenId, chainName[chain], data, amount);
        }
    }

    function _bytesToAddress(bytes32 bys) private pure returns (address addr) {
        return address(uint160(uint256(bys)));
    }
}
