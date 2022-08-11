// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import '../StableSwapERC20.sol';

contract ERC20 is StableSwapERC20 {
    constructor(uint _totalSupply) {
        _mint(msg.sender, _totalSupply);
    }
}
