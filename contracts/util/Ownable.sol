// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

contract Ownable {

    address immutable internal owner;
    modifier onlyOwner() {
        require(msg.sender == owner, 'Nomiswap: FORBIDDEN');
        _;
    }

    constructor(address _owner) {
        owner = _owner;
    }

}