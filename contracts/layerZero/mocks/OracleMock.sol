// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
import "@openzeppelin/contracts/access/Ownable.sol";

contract OracleMock is Ownable {
    event SetPrice(bytes32 symbol, uint price);

    mapping(bytes32 => uint) public prices;

    function setPrice(
        bytes32[] memory _symbols,
        uint[] memory _prices
    ) external onlyOwner {
        require(_symbols.length == _prices.length, "Invalid params");
        for (uint i = 0; i < _symbols.length; i++) {
            prices[_symbols[i]] = _prices[i];
            emit SetPrice(_symbols[i], _prices[i]);
        }
    }

    function getPrices(
        bytes32[] memory _symbols
    ) external view returns (uint[] memory results) {
        results = new uint[](_symbols.length);
        for (uint i = 0; i < _symbols.length; i++) {
            uint price = prices[_symbols[i]];
            require(price > 0, "Price not set up");
            results[i] = price;
        }
    }

    function getSinglePrice(
        bytes32 _symbol
    ) external view returns (uint result) {
        result = prices[_symbol];
        require(result > 0, "Price not set up");
    }
}
