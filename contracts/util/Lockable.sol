// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

contract Lockable {

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'Nomiswap: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

}