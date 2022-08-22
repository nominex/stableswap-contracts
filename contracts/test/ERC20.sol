// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.15;

import '../NomiswapStableERC20.sol';

contract ERC20 is NomiswapStableERC20 {
    constructor(uint _totalSupply) {
        _mint(msg.sender, _totalSupply);
    }

    function symbol() external pure returns (string memory) {
        return "ERC20";
    }
}
