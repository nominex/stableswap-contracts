// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import './StableSwapPair.sol';


library FactoryLib {
    function pairCreationCode() external pure returns(bytes memory) {
        return type(StableSwapPair).creationCode;
    }
}

