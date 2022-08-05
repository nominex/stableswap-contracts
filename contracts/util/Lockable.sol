// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

contract Lockable {

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'Nomiswap: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

}