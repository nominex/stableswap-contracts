pragma solidity =0.5.16;

import '../NomiswapERC20.sol';

contract ERC20 is NomiswapERC20 {
    constructor(uint _totalSupply) public {
        _mint(msg.sender, _totalSupply);
    }
}
