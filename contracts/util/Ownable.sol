// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

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