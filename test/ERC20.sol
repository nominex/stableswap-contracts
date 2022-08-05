pragma solidity >=0.8.0;

import '../contracts/StableSwapERC20.sol';

contract ERC20 is StableSwapERC20 {
    constructor(uint _totalSupply) {
        _mint(msg.sender, _totalSupply);
    }
}
